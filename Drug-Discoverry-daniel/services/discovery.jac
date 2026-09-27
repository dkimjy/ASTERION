import from rdkit { Chem }
import from rdkit.Chem { AllChem, Crippen, Descriptors, Lipinski }
import from uuid { uuid4 }

node Target {
    has run_id: str = "";
    has name: str = "";
    has disease_context: str = "";
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

node Candidate {
    has run_id: str = "";
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
}

edge DerivedFrom: Candidate --> Candidate {
    has mutation_applied: str = "";
}

obj JacGraphNode {
    has node_id: str;
    has node_type: str;
    has label: str;
    has detail: str;
    has generation: int = -1;
}

obj JacGraphEdge {
    has source: str;
    has target: str;
    has edge_type: str;
    has label: str;
}

obj JacWalkerTrace {
    has name: str;
    has status: str;
    has route: list[str];
    has visited_count: int;
}

obj JacGraphView {
    has nodes: list[JacGraphNode];
    has edges: list[JacGraphEdge];
    has walker: JacWalkerTrace;
}

walker DiscoveryGraphWalker {
    has run_id: str;
    has nodes: list[JacGraphNode] = [];
    has edges: list[JacGraphEdge] = [];
    has route: list[str] = [];
    has reports: list[JacGraphView] = [];

    can begin_graph with Root entry {
        self.nodes.append(JacGraphNode(node_id="root", node_type="Root", label="Graph root", detail="Current run entry point"));
        self.route.append("Root");
        visit [here -->];
    }

    can capture_target with Target entry {
        if here.run_id != self.run_id { skip; }
        target_id = "target-" + self.run_id;
        self.nodes.append(JacGraphNode(node_id=target_id, node_type="Target", label=here.name, detail=here.disease_context));
        self.edges.append(JacGraphEdge(source="root", target=target_id, edge_type="Untyped", label="root attachment"));
        self.route.append("Target: " + here.name);
    }

    can capture_candidate with Candidate entry {
        if here.run_id != self.run_id { skip; }
        candidate_id = "candidate-" + str(here.generation);
        detail = "RDKit screen passed" if here.lipinski_pass else "Review descriptor thresholds";
        self.nodes.append(JacGraphNode(node_id=candidate_id, node_type="Candidate", label="Generation " + str(here.generation), detail=detail, generation=here.generation));
        if here.generation == 0 {
            self.edges.append(JacGraphEdge(source="root", target=candidate_id, edge_type="Untyped", label="root attachment"));
        } else {
            self.edges.append(JacGraphEdge(source="candidate-" + str(here.generation - 1), target=candidate_id, edge_type="DerivedFrom", label=here.mutation_applied));
        }
        self.route.append("Candidate generation " + str(here.generation));
        visit [here ->:DerivedFrom:->];
    }

    can finish_graph with Root exit {
        if len(self.nodes) > 1 {
            trace = JacWalkerTrace(name="DiscoveryGraphWalker", status="Complete", route=self.route, visited_count=len(self.route));
            report JacGraphView(nodes=self.nodes, edges=self.edges, walker=trace);
        }
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
}

obj DiscoveryResult {
    has target_name: str;
    has disease_context: str;
    has candidates: list[CandidateView];
    has graph: JacGraphView;
    has docking_status: str;
    has scope_note: str;
}

def _describe_candidate(smiles: str, generation: int, mutation: str) -> Candidate {
    chem_module: any = Chem as any;
    descriptor_module: any = Descriptors as any;
    crippen_module: any = Crippen as any;
    lipinski_module: any = Lipinski as any;
    embedding_module: any = AllChem as any;

    molecule: any = chem_module.MolFromSmiles(smiles);
    if molecule is None {
        raise ValueError("The generated SMILES string is not valid.");
    }

    mol_weight: float = descriptor_module.MolWt(molecule) as float;
    logp_value: float = crippen_module.MolLogP(molecule) as float;
    donor_count: int = lipinski_module.NumHDonors(molecule) as int;
    acceptor_count: int = lipinski_module.NumHAcceptors(molecule) as int;
    passed: bool = mol_weight <= 500.0 and logp_value <= 5.0 and donor_count <= 5 and acceptor_count <= 10;

    logp_delta: float = 0.0;
    weight_delta: float = 0.0;
    if logp_value > 2.5 { logp_delta = logp_value - 2.5; }
    else { logp_delta = 2.5 - logp_value; }
    if mol_weight > 300.0 { weight_delta = mol_weight - 300.0; }
    else { weight_delta = 300.0 - mol_weight; }
    score: float = 0.92 - logp_delta * 0.035 - weight_delta * 0.0003;
    if mol_weight > 500.0 { score = score - 0.22; }
    if logp_value > 5.0 { score = score - 0.20; }
    if donor_count > 5 { score = score - 0.12; }
    if acceptor_count > 10 { score = score - 0.10; }
    if score < 0.0 { score = 0.0; }
    if score > 1.0 { score = 1.0; }

    reason: str = "RDKit descriptor screen passed the configured Lipinski thresholds.";
    if mol_weight > 500.0 {
        reason = "Molecular weight exceeds 500 Da.";
    } elif logp_value > 5.0 {
        reason = "Calculated LogP exceeds 5.";
    } elif donor_count > 5 {
        reason = "Hydrogen-bond donor count exceeds 5.";
    } elif acceptor_count > 10 {
        reason = "Hydrogen-bond acceptor count exceeds 10.";
    }

    conformer_molecule: any = chem_module.AddHs(molecule) as any;
    embed_status: int = embedding_module.EmbedMolecule(conformer_molecule, randomSeed=4100 + generation) as int;
    if embed_status < 0 {
        raise ValueError("RDKit could not generate a 3D conformer for this candidate.");
    }
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

    return Candidate(smiles=smiles, atoms=atom_views, bonds=bond_views, generation=generation, mol_weight=mol_weight, logp=logp_value, h_donors=donor_count, h_acceptors=acceptor_count, lipinski_pass=passed, proxy_score=score, failure_reason=reason, mutation_applied=mutation);
}

def:pub run_discovery(target_name: str, disease_context: str, seed_smiles: str) -> DiscoveryResult {
    if not target_name.strip() or not seed_smiles.strip() {
        raise ValueError("Enter a target and a seed SMILES string.");
    }

    run_id = str(uuid4());
    target = Target(run_id=run_id, name=target_name.strip(), disease_context=disease_context.strip());
    root ++> target;
    seed = seed_smiles.strip();
    generation_count = 4;
    candidates: list[Candidate] = [];
    previous: Candidate | None = None;

    for generation in range(generation_count) {
        smiles = seed;
        mutation = "Seed molecule";
        if generation == 1 {
            mutation = "Hydroxyl substitution hypothesis";
            if "O" not in seed { smiles = seed + "O"; }
        } elif generation == 2 {
            mutation = "Nitrogen substitution hypothesis";
            if "N" not in seed { smiles = seed + "N"; }
        } elif generation == 3 {
            mutation = "Polarity adjustment hypothesis";
            smiles = seed + "O";
            if "N" not in smiles { smiles = smiles + "N"; }
        }

        candidate = _describe_candidate(smiles, generation, mutation);
        candidate.run_id = run_id;
        if previous is None {
            root ++> candidate;
        } else {
            prior = previous as Candidate;
            prior +>:DerivedFrom(mutation_applied=mutation):+> candidate;
        }
        candidates.append(candidate);
        previous = candidate;
    }

    views: list[CandidateView] = [];
    for candidate in candidates {
        views.append(CandidateView(smiles=candidate.smiles, atoms=candidate.atoms, bonds=candidate.bonds, generation=candidate.generation, mol_weight=candidate.mol_weight, logp=candidate.logp, h_donors=candidate.h_donors, h_acceptors=candidate.h_acceptors, lipinski_pass=candidate.lipinski_pass, proxy_score=candidate.proxy_score, failure_reason=candidate.failure_reason, mutation_applied=candidate.mutation_applied));
    }

    graph_walk = root spawn DiscoveryGraphWalker(run_id=run_id);
    if len(graph_walk.reports) == 0 {
        raise ValueError("The Jac graph walker did not return a graph snapshot.");
    }
    graph = graph_walk.reports[0];

    return DiscoveryResult(target_name=target.name, disease_context=target.disease_context, candidates=views, graph=graph, docking_status="Not run", scope_note="RDKit validates SMILES, generates a 3D conformer for each candidate, and computes molecular descriptors. The entered target is recorded but does not condition the demo scaffold edits or proxy ranking. Target resolution, protein lookup, PDB retrieval, and AutoDock Vina docking are not run.");
}
