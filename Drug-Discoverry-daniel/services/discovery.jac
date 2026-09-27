import from rdkit { Chem }
import from rdkit.Chem { AllChem, Crippen, Descriptors, Lipinski }
import importlib;
import from services.evidence { EvidenceView, gather_target_evidence }

node Target {
    has name: str = "";
    has disease_context: str = "";
    has pathway: str = "";
}

node EvidenceRecord {
    has category: str = "";
    has label: str = "";
    has detail: str = "";
}

obj AtomView {
    has element: str;
    has x: float;
    has y: float;
    has z: float;
}

obj BondView {
    has begin: int;
    has end: int;
    has order: float;
}

obj MutationRule {
    has label: str;
    has reaction_smarts: str = "";
    has product_smiles: str = "";
}

node Candidate {
    has smiles: str = "";
    has atoms: list[AtomView] = [];
    has bonds: list[BondView] = [];
    has generation: int = 0;
    has mol_weight: float = 0.0;
    has logp: float = 0.0;
    has h_donors: int = 0;
    has h_acceptors: int = 0;
    has lipinski_pass: bool = False;
    has proxy_score: float = 0.0;
    has failure_reason: str = "";
    has mutation_applied: str = "Seed molecule";
    has decision_reason: str = "";
}

edge DerivedFrom: Candidate --> Candidate {
    has mutation_applied: str = "";
}

edge StartsWith: Target --> Candidate {}
edge HasEvidence: Target --> EvidenceRecord {}

walker RefinementTrace {
    has events: list[str] = [];
    has reports: list[list[str]] = [];

    can enter_target with Target entry {
        self.events.append("NODE · Target · " + here.name);
        evidence_nodes = [here ->:HasEvidence:->];
        if len(evidence_nodes) > 0 {
            self.events.append("EDGE · Target → Evidence");
            visit evidence_nodes;
        }
        seed_nodes = [here ->:StartsWith:->];
        if len(seed_nodes) > 0 {
            self.events.append("EDGE · Target → Seed candidate");
            visit seed_nodes;
        }
    }

    can enter_evidence with EvidenceRecord entry {
        self.events.append("NODE · " + here.category + " · " + here.label);
    }

    can enter_candidate with Candidate entry {
        self.events.append("NODE · Candidate generation " + str(here.generation));
        next_generation = [here ->:DerivedFrom:->];
        if len(next_generation) > 0 {
            self.events.append("EDGE · DerivedFrom · " + here.mutation_applied);
            visit next_generation;
        }
    }

    can finish with Target exit {
        report self.events;
    }
}

obj CandidateView {
    has smiles: str;
    has atoms: list[AtomView];
    has bonds: list[BondView];
    has generation: int;
    has mol_weight: float;
    has logp: float;
    has h_donors: int;
    has h_acceptors: int;
    has lipinski_pass: bool;
    has proxy_score: float;
    has failure_reason: str;
    has mutation_applied: str;
    has decision_reason: str;
}

obj DiscoveryResult {
    has target_name: str;
    has disease_context: str;
    has pathway_name: str;
    has candidates: list[CandidateView];
    has evidence: list[EvidenceView];
    has graph_trace: list[str];
    has docking_status: str;
    has agent_summary: str;
    has scope_note: str;
}

def _distance(value: float, target: float) -> float {
    difference: float = value - target;
    if difference < 0.0 { difference = difference * -1.0; }
    return difference;
}

def:pub validate_smiles(smiles: str) -> bool {
    molecule: any = (Chem as any).MolFromSmiles(smiles.strip());
    return molecule is not None;
}

def _property_score(mol_weight: float, logp: float, donors: int, acceptors: int) -> float {
    score: float = 1.0 - (_distance(mol_weight, 350.0) * 0.0012) - (_distance(logp, 2.0) * 0.12);
    if donors > 3 { score = score - (donors - 3) * 0.08; }
    if acceptors > 7 { score = score - (acceptors - 7) * 0.05; }
    if mol_weight > 500.0 { score = score - 0.25; }
    if logp > 5.0 { score = score - 0.20; }
    if donors > 5 { score = score - 0.12; }
    if acceptors > 10 { score = score - 0.10; }
    if score < 0.0 { score = 0.0; }
    if score > 1.0 { score = 1.0; }
    return score;
}

def _describe_candidate(smiles: str, generation: int, mutation: str, decision: str) -> Candidate {
    chem_module: any = Chem as any;
    descriptor_module: any = Descriptors as any;
    crippen_module: any = Crippen as any;
    lipinski_module: any = Lipinski as any;
    embedding_module: any = AllChem as any;

    molecule: any = chem_module.MolFromSmiles(smiles);
    if molecule is None { raise ValueError("RDKit rejected a proposed molecule."); }

    mol_weight: float = descriptor_module.MolWt(molecule) as float;
    logp_value: float = crippen_module.MolLogP(molecule) as float;
    donor_count: int = lipinski_module.NumHDonors(molecule) as int;
    acceptor_count: int = lipinski_module.NumHAcceptors(molecule) as int;
    passed: bool = mol_weight <= 500.0 and logp_value <= 5.0 and donor_count <= 5 and acceptor_count <= 10;
    score: float = _property_score(mol_weight, logp_value, donor_count, acceptor_count);

    reason: str = "Within configured Rule-of-Five descriptor limits.";
    if mol_weight > 500.0 { reason = "Molecular weight exceeds 500 Da."; }
    elif logp_value > 5.0 { reason = "Calculated LogP exceeds 5."; }
    elif donor_count > 5 { reason = "Hydrogen-bond donor count exceeds 5."; }
    elif acceptor_count > 10 { reason = "Hydrogen-bond acceptor count exceeds 10."; }

    conformer_molecule: any = chem_module.AddHs(molecule) as any;
    embed_status: int = embedding_module.EmbedMolecule(conformer_molecule, randomSeed=4100 + generation) as int;
    if embed_status < 0 { raise ValueError("RDKit could not generate a 3D conformer for this candidate."); }
    conformer: any = conformer_molecule.GetConformer() as any;
    atom_views: list[AtomView] = [];
    for atom_index in range(int(molecule.GetNumAtoms())) {
        atom: any = molecule.GetAtomWithIdx(atom_index) as any;
        position: any = conformer.GetAtomPosition(atom_index) as any;
        atom_views.append(AtomView(element=str(atom.GetSymbol()), x=position.x as float, y=position.y as float, z=position.z as float));
    }
    bond_views: list[BondView] = [];
    for bond in molecule.GetBonds() {
        bond_views.append(BondView(begin=bond.GetBeginAtomIdx() as int, end=bond.GetEndAtomIdx() as int, order=bond.GetBondTypeAsDouble() as float));
    }
    return Candidate(smiles=smiles, atoms=atom_views, bonds=bond_views, generation=generation, mol_weight=mol_weight, logp=logp_value, h_donors=donor_count, h_acceptors=acceptor_count, lipinski_pass=passed, proxy_score=score, failure_reason=reason, mutation_applied=mutation, decision_reason=decision);
}

def _propose_edits(smiles: str) -> list[MutationRule] {
    chem_module: any = Chem as any;
    reaction_module: any = importlib.import_module("rdkit.Chem.rdChemReactions") as any;
    molecule: any = chem_module.MolFromSmiles(smiles);
    proposals: list[MutationRule] = [];
    seen: set[str] = set();
    rules: list[MutationRule] = [
        MutationRule(label="Replace aromatic H with hydroxyl", reaction_smarts="[cH:1]>>[c:1]O", product_smiles=""),
        MutationRule(label="Replace aromatic H with fluorine", reaction_smarts="[cH:1]>>[c:1]F", product_smiles=""),
        MutationRule(label="Replace aromatic H with amino", reaction_smarts="[cH:1]>>[c:1]N", product_smiles=""),
        MutationRule(label="Hydroxylate a methyl substituent", reaction_smarts="[CH3:1]>>[CH2:1]O", product_smiles=""),
    ];
    for rule in rules {
        reaction: any = reaction_module.ReactionFromSmarts(rule.reaction_smarts) as any;
        products: any = reaction.RunReactants((molecule,)) as any;
        for product_set in products {
            try {
                product: any = product_set[0] as any;
                chem_module.SanitizeMol(product);
                product_smiles: str = chem_module.MolToSmiles(product) as str;
                if product_smiles not in seen and product_smiles != smiles {
                    seen.add(product_smiles);
                    proposals.append(MutationRule(label=rule.label, product_smiles=product_smiles));
                }
            } except Exception { }
        }
    }
    return proposals;
}

def _best_candidate(candidates: list[Candidate]) -> Candidate {
    best: Candidate = candidates[0];
    for candidate in candidates {
        if candidate.proxy_score > best.proxy_score { best = candidate; }
    }
    return best;
}

def:pub run_discovery(target_name: str, disease_context: str, pathway_name: str, seed_smiles: str) -> DiscoveryResult {
    if not target_name.strip() or not seed_smiles.strip() {
        raise ValueError("Enter a target and a seed SMILES string.");
    }

    target = Target(name=target_name.strip(), disease_context=disease_context.strip(), pathway=pathway_name.strip());
    root ++> target;
    seed_molecule: any = (Chem as any).MolFromSmiles(seed_smiles.strip());
    if seed_molecule is None { raise ValueError("The seed SMILES is invalid."); }
    canonical_seed: str = (Chem as any).MolToSmiles(seed_molecule) as str;
    parent = _describe_candidate(canonical_seed, 0, "Seed molecule", "Starting point supplied by the researcher.");
    candidates: list[Candidate] = [parent];
    previous: Candidate = parent;
    visited: set[str] = {canonical_seed};
    rounds_completed: int = 0;
    stop_reason: str = "The refinement budget was reached.";

    for generation in range(1, 5) {
        proposals = _propose_edits(previous.smiles);
        options: list[Candidate] = [];
        for proposal in proposals {
            if proposal.product_smiles in visited { continue; }
            visited.add(proposal.product_smiles);
            try {
                candidate = _describe_candidate(proposal.product_smiles, generation, proposal.label, "Proposed by an RDKit reaction rule and evaluated against the configured descriptor profile.");
                options.append(candidate);
            } except Exception { }
        }
        if len(options) == 0 {
            stop_reason = "No unseen, chemically valid edits were available.";
            break;
        }
        selected = _best_candidate(options);
        chosen = _describe_candidate(selected.smiles, generation, selected.mutation_applied, "Selected over " + str(len(options)) + " valid proposals after RDKit evaluation.");
        if chosen.proxy_score <= previous.proxy_score + 0.001 {
            stop_reason = "Stopped because no proposed edit improved the property-balance score.";
            break;
        }
        chosen.decision_reason = "Selected over " + str(len(proposals)) + " generated edits: its property-balance score improved from " + str(previous.proxy_score) + " to " + str(chosen.proxy_score) + ". This is not a binding prediction.";
        previous +>:DerivedFrom(mutation_applied=chosen.mutation_applied):+> chosen;
        candidates.append(chosen);
        previous = chosen;
        rounds_completed = generation;
    }

    evidence = gather_target_evidence(target.name, target.pathway);
    target +>:StartsWith():+> parent;
    for item in evidence {
        evidence_node = EvidenceRecord(category=item.category, label=item.label, detail=item.detail);
        target +>:HasEvidence():+> evidence_node;
    }
    trace_result = target spawn RefinementTrace();
    graph_trace: list[str] = [];
    if len(trace_result.reports) > 0 { graph_trace = trace_result.reports[0]; }
    views: list[CandidateView] = [];
    for candidate in candidates {
        views.append(CandidateView(smiles=candidate.smiles, atoms=candidate.atoms, bonds=candidate.bonds, generation=candidate.generation, mol_weight=candidate.mol_weight, logp=candidate.logp, h_donors=candidate.h_donors, h_acceptors=candidate.h_acceptors, lipinski_pass=candidate.lipinski_pass, proxy_score=candidate.proxy_score, failure_reason=candidate.failure_reason, mutation_applied=candidate.mutation_applied, decision_reason=candidate.decision_reason));
    }

    summary: str = "The agent ran " + str(rounds_completed) + " improving edit round(s), generated " + str(len(visited) - 1) + " unique valid proposals, and stopped: " + stop_reason;
    return DiscoveryResult(target_name=target.name, disease_context=target.disease_context, pathway_name=target.pathway, candidates=views, evidence=evidence, graph_trace=graph_trace, docking_status="Not run", agent_summary=summary, scope_note="KEGG pathway and DGIdb interaction records are evidence for target context only. RDKit enumerates reaction-rule analogs and ranks a drug-like descriptor profile; it does not predict target binding. Protein structure retrieval and AutoDock Vina docking are not connected yet.");
}
