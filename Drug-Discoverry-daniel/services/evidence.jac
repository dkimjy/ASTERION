import json;
import from urllib.request { Request, urlopen }
import from urllib.parse { quote }

obj EvidenceView {
    has category: str;
    has label: str;
    has detail: str;
    has source: str;
    has url: str;
}

def _get_text(url: str) -> str {
    try {
        response: any = urlopen(url, timeout=5) as any;
        raw: any = response.read();
        return raw.decode("utf-8") as str;
    } except Exception {
        return "";
    }
}

def _kegg_gene_id(query: str) -> tuple[str, str] {
    safe_query: str = quote(query.strip(), safe="");
    response_text: str = _get_text("https://rest.kegg.jp/find/hsa/" + safe_query);
    for line in response_text.splitlines() {
        fields = line.split("\t");
        if len(fields) > 1 and fields[0].startswith("hsa:") {
            aliases: list[str] = fields[1].split(";")[0].split(",");
            for alias in aliases {
                if alias.strip().lower() == query.strip().lower() {
                    return (fields[0], alias.strip());
                }
            }
        }
    }
    return ("", "");
}

def _pathway_result(query: str) -> tuple[str, str] {
    safe_query: str = quote(query.strip(), safe="");
    response_text: str = _get_text("https://rest.kegg.jp/find/pathway/" + safe_query);
    for line in response_text.splitlines() {
        fields = line.split("\t");
        if len(fields) > 1 and (fields[0].startswith("hsa") or fields[0].startswith("map")) {
            pathway_id: str = fields[0];
            if pathway_id.startswith("map") { pathway_id = "hsa" + pathway_id.replace("map", ""); }
            pathway_record: str = _get_text("https://rest.kegg.jp/get/" + quote(pathway_id, safe=":"));
            if pathway_record != "" {
                for detail_line in pathway_record.splitlines() {
                    if detail_line.startswith("NAME") { return (pathway_id, detail_line.replace("NAME", "").strip()); }
                }
            }
        }
    }
    return ("", "");
}

def _pathway_for_gene(gene_id: str) -> tuple[str, str] {
    response_text: str = _get_text("https://rest.kegg.jp/link/pathway/" + quote(gene_id, safe=":"));
    for line in response_text.splitlines() {
        fields = line.split("\t");
        if len(fields) > 1 and fields[1].startswith("hsa") {
            pathway_id: str = fields[1];
            pathway_text: str = _get_text("https://rest.kegg.jp/get/" + quote(pathway_id, safe=":"));
            for detail_line in pathway_text.splitlines() {
                if detail_line.startswith("NAME") {
                    pathway_title: str = detail_line.replace("NAME", "").strip();
                    return (pathway_id, pathway_title);
                }
            }
        }
    }
    return ("", "");
}

def _pathway_genes(pathway_id: str) -> list[EvidenceView] {
    evidence: list[EvidenceView] = [];
    response_text: str = _get_text("https://rest.kegg.jp/link/hsa/" + quote(pathway_id, safe=":"));
    seen: set[str] = set();
    gene_ids: list[str] = [];
    for line in response_text.splitlines() {
        fields = line.split("\t");
        if len(fields) > 1 and fields[1].startswith("hsa:") and fields[1] not in seen {
            seen.add(fields[1]);
            gene_ids.append(fields[1]);
            if len(gene_ids) >= 8 { break; }
        }
    }
    if len(gene_ids) == 0 { return evidence; }
    joined_ids: str = "+".join(gene_ids);
    records: str = _get_text("https://rest.kegg.jp/get/" + quote(joined_ids, safe=":+"));
    current_id: str = "";
    current_name: str = "";
    for line in records.splitlines() + ["///"] {
        if line.startswith("ENTRY") {
            entry_fields: list[str] = line.replace("ENTRY", "").strip().split();
            current_id = "hsa:" + entry_fields[0] if len(entry_fields) > 0 else "";
        } elif line.startswith("NAME") {
            current_name = line.replace("NAME", "").split(";")[0].strip();
        } elif line.startswith("///") {
            if current_id != "" and current_name != "" {
                evidence.append(EvidenceView(category="Pathway gene", label=current_name, detail="KEGG gene " + current_id + " is linked to this human pathway.", source="KEGG", url="https://www.kegg.jp/entry/" + pathway_id));
            }
            current_id = "";
            current_name = "";
        }
    }
    return evidence;
}

def _dgidb_interactions(gene_names: list[str]) -> list[EvidenceView] {
    evidence: list[EvidenceView] = [];
    if len(gene_names) == 0 { return evidence; }
    query: str = "query($names:[String!]!){genes(names:$names){nodes{name interactions{drug{name} interactionScore interactionTypes{type directionality} sources{sourceDbName}}}}}";
    payload: str = json.dumps({"query": query, "variables": {"names": gene_names}});
    headers: dict[str, str] = {"Content-Type": "application/json", "Accept": "application/json", "User-Agent": "Asterion-Discovery/1.0"};
    try {
        request = Request("https://dgidb.org/api/graphql", data=payload.encode("utf-8"), headers=headers, method="POST");
        response: any = urlopen(request, timeout=8) as any;
        raw_body: any = response.read();
        body: str = raw_body.decode("utf-8") as str;
        parsed: any = json.loads(body);
        if "errors" in parsed {
            error_text: str = str(parsed["errors"]);
            evidence.append(EvidenceView(category="Evidence status", label="DGIdb query returned an error", detail=error_text[:240], source="DGIdb", url="https://dgidb.org/api"));
            return evidence;
        }
        nodes: list[any] = parsed["data"]["genes"]["nodes"] as list[any];
        for gene in nodes {
            gene_name: str = gene["name"] as str;
            interactions: list[any] = gene["interactions"] as list[any];
            for interaction in interactions {
                drug: any = interaction["drug"];
                drug_name: str = drug["name"] as str;
                interaction_types: list[any] = interaction["interactionTypes"] as list[any];
                type_names: list[str] = [];
                for interaction_type in interaction_types {
                    type_names.append(str(interaction_type["type"]));
                }
                source_records: list[any] = interaction["sources"] as list[any];
                source_names: list[str] = [];
                for source_record in source_records {
                    source_names.append(str(source_record["sourceDbName"]));
                }
                score_text: str = "DGIdb interaction score " + str(interaction["interactionScore"]) + ". ";
                detail: str = score_text + (", ".join(type_names) if len(type_names) > 0 else "Reported drug–gene interaction") + ".";
                if len(source_names) > 0 { detail = detail + " Sources: " + ", ".join(source_names) + "."; }
                evidence.append(EvidenceView(category="Drug–gene interaction", label=drug_name + " ↔ " + gene_name, detail=detail, source="DGIdb", url="https://dgidb.org/api"));
                if len(evidence) >= 12 { return evidence; }
            }
        }
    } except Exception as error {
        evidence.append(EvidenceView(category="Evidence status", label="DGIdb request failed", detail=str(error)[:240], source="DGIdb", url="https://dgidb.org/api"));
    }
    return evidence;
}

def:pub gather_target_evidence(target_name: str, pathway_name: str) -> list[EvidenceView] {
    evidence: list[EvidenceView] = [];
    target_term: str = target_name.strip().split(" ")[0];
    (gene_id, matched_symbol) = _kegg_gene_id(target_term);
    gene_symbol: str = target_name.strip();
    if gene_id != "" {
        gene_symbol = matched_symbol;
        kegg_gene_record: str = _get_text("https://rest.kegg.jp/get/" + quote(gene_id, safe=":"));
        for line in kegg_gene_record.splitlines() {
            if line.startswith("NAME") {
                gene_symbol = line.replace("NAME", "").split(";")[0].strip();
                break;
            }
        }
        evidence.append(EvidenceView(category="Resolved target", label=gene_symbol, detail="Resolved to KEGG human gene " + gene_id + ".", source="KEGG", url="https://www.kegg.jp/entry/" + gene_id));
    }

    pathway_id: str = "";
    pathway_title: str = "";
    if pathway_name.strip() != "" {
        pathway_terms: list[str] = pathway_name.split("/");
        clean_pathway: str = pathway_terms[len(pathway_terms) - 1].strip();
        (pathway_id, pathway_title) = _pathway_result(clean_pathway);
    }
    if pathway_id == "" and gene_id != "" {
        (pathway_id, pathway_title) = _pathway_for_gene(gene_id);
    }
    if pathway_id != "" {
        evidence.append(EvidenceView(category="KEGG pathway", label=pathway_title, detail="Human KEGG pathway " + pathway_id + " matched the target context.", source="KEGG", url="https://www.kegg.jp/entry/" + pathway_id));
        pathway_gene_evidence: list[EvidenceView] = _pathway_genes(pathway_id);
        for pathway_gene in pathway_gene_evidence { evidence.append(pathway_gene); }
    }

    query_genes: list[str] = [];
    if gene_id != "" { query_genes.append(target_term); }
    for pathway_gene in evidence {
        if pathway_gene.category == "Pathway gene" and len(query_genes) < 8 and pathway_gene.label not in query_genes {
            query_genes.append(pathway_gene.label);
        }
    }
    interaction_evidence: list[EvidenceView] = _dgidb_interactions(query_genes);
    for interaction in interaction_evidence { evidence.append(interaction); }

    if gene_id == "" {
        evidence.append(EvidenceView(category="Evidence status", label="KEGG target not resolved", detail="No exact human KEGG gene match was found for this target label. DGIdb was queried using the entered name where possible.", source="KEGG", url="https://rest.kegg.jp/"));
    }
    if pathway_id == "" {
        evidence.append(EvidenceView(category="Evidence status", label="Pathway not resolved", detail="No matching human KEGG pathway was found from the supplied pathway and target terms.", source="KEGG", url="https://rest.kegg.jp/"));
    }
    if len(interaction_evidence) == 0 {
        evidence.append(EvidenceView(category="Evidence status", label="No DGIdb interactions returned", detail="No matching records were returned, or the DGIdb query was unavailable.", source="DGIdb", url="https://dgidb.org/api"));
    }
    return evidence;
}
