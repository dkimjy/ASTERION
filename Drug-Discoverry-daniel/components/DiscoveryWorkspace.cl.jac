sv import from ..services.discovery { AtomView, BondView, CandidateView, JacGraphView, run_discovery }
import from .ui.button { Button }
import from .ui.input { Input }
import from .JacGraphPanel { JacGraphPanel }
cl import from "@hugeicons/react" { HugeiconsIcon }
cl import from "@hugeicons/core-free-icons" { SparklesIcon, Atom01Icon, Alert01Icon, CheckmarkCircle01Icon }

obj ScreenPoint {
    has x: float;
    has y: float;
    has depth: float;
    has radius: float;
    has element: str;
}

def _project_atom(atom: AtomView, rotation_x: float, rotation_y: float, zoom: float) -> ScreenPoint {
    cosine_y: float = Math.cos(rotation_y) as float;
    sine_y: float = Math.sin(rotation_y) as float;
    cosine_x: float = Math.cos(rotation_x) as float;
    sine_x: float = Math.sin(rotation_x) as float;
    rotated_x: float = atom.x * cosine_y + atom.z * sine_y;
    depth: float = atom.z * cosine_y - atom.x * sine_y;
    rotated_y: float = atom.y * cosine_x - depth * sine_x;
    rotated_depth: float = atom.y * sine_x + depth * cosine_x;
    perspective: float = 1.0 + rotated_depth * 0.035;
    if perspective < 0.65 { perspective = 0.65; }
    radius: float = 10.0 * zoom * perspective;
    if atom.element == "O" or atom.element == "N" or atom.element == "F" { radius = 9.0 * zoom * perspective; }
    if atom.element == "S" or atom.element == "P" or atom.element == "Cl" or atom.element == "Br" { radius = 12.0 * zoom * perspective; }
    return ScreenPoint(x=260.0 + rotated_x * 32.0 * zoom * perspective, y=145.0 - rotated_y * 32.0 * zoom * perspective, depth=rotated_depth, radius=radius, element=atom.element);
}

def:pub MoleculeViewer(atoms: list[AtomView], bonds: list[BondView], generation: int, instance_id: str, className: str = "") -> JsxElement {
    has rotation_x: float = 0.28;
    has rotation_y: float = -0.48;
    has zoom: float = 1.0;
    has dragging: bool = False;
    has pointer_x: float = 0.0;
    has pointer_y: float = 0.0;

    def start_drag(e: MouseEvent) {
        e.preventDefault();
        dragging = True;
        pointer_x = e.clientX as float;
        pointer_y = e.clientY as float;
    }
    def rotate_molecule(e: MouseEvent) {
        if dragging {
            delta_x: float = (e.clientX as float) - pointer_x;
            delta_y: float = (e.clientY as float) - pointer_y;
            rotation_y = rotation_y + delta_x * 0.009;
            rotation_x = rotation_x + delta_y * 0.009;
            pointer_x = e.clientX as float;
            pointer_y = e.clientY as float;
        }
    }
    def stop_drag(e: MouseEvent) { dragging = False; }
    def zoom_molecule(e: WheelEvent) {
        e.preventDefault();
        next_zoom: float = zoom * (1.0 - (e.deltaY as float) * 0.001);
        if next_zoom < 0.55 { next_zoom = 0.55; }
        if next_zoom > 1.8 { next_zoom = 1.8; }
        zoom = next_zoom;
    }
    def reset_molecule(e: MouseEvent) {
        rotation_x = 0.28;
        rotation_y = -0.48;
        zoom = 1.0;
    }

    points: list[ScreenPoint] = [];
    for atom in atoms {
        points.append(_project_atom(atom, rotation_x, rotation_y, zoom));
    }

    return <div className={"molecule-viewer " + className} data-viewer-id={instance_id}>
        <div className="viewer-toolbar">
            <span><strong>3D CONFORMER</strong><small>Drag to rotate · scroll to zoom</small></span>
            <button type="button" className="viewer-reset" onClick={reset_molecule}>Reset view</button>
        </div>
        <svg className={"molecule-stage " + ("is-dragging" if dragging else "")} viewBox="0 0 520 290" role="img" aria-label={"Interactive 3D molecular model for generation " + str(generation)} onMouseDown={start_drag} onMouseMove={rotate_molecule} onMouseUp={stop_drag} onMouseLeave={stop_drag} onWheel={zoom_molecule}>
            <rect x="0" y="0" width="520" height="290" fill="#0c1015" />
            <g className="molecule-bonds">
                {for bond in bonds {
                    start_point = points[bond.begin];
                    end_point = points[bond.end];
                    delta_x: float = end_point.x - start_point.x;
                    delta_y: float = end_point.y - start_point.y;
                    bond_length: float = Math.sqrt(delta_x * delta_x + delta_y * delta_y) as float;
                    if bond_length < 0.001 { bond_length = 1.0; }
                    normal_x: float = -delta_y / bond_length;
                    normal_y: float = delta_x / bond_length;
                    offsets: list[float] = [0.0];
                    if bond.order > 1.5 { offsets = [-3.2, 3.2]; }
                    if bond.order > 2.5 { offsets = [-6.0, 0.0, 6.0]; }
                    <g key={str(bond.begin) + "-" + str(bond.end)}>
                        {for offset in offsets {
                            x1: float = start_point.x + normal_x * offset;
                            y1: float = start_point.y + normal_y * offset;
                            x2: float = end_point.x + normal_x * offset;
                            y2: float = end_point.y + normal_y * offset;
                            <g key={str(bond.begin) + "-" + str(bond.end) + "-" + str(offset)}>
                                <line x1={x1} y1={y1} x2={x2} y2={y2} className="bond-shadow" />
                                <line x1={x1} y1={y1} x2={x2} y2={y2} className="bond-cylinder" />
                            </g>
                        }}
                    </g>
                }}
            </g>
            <g className="molecule-atoms">
                {for (atom_index, atom) in enumerate(atoms) {
                    point = points[atom_index];
                    <g key={str(atom_index)}>
                        <circle cx={point.x} cy={point.y} r={point.radius} className={"atom-sphere atom-" + atom.element} />
                        <circle cx={point.x - point.radius * 0.31} cy={point.y - point.radius * 0.32} r={point.radius * 0.24} className="atom-highlight" />
                        <text x={point.x} y={point.y + 3.0} textAnchor="middle" className="atom-label">{atom.element}</text>
                    </g>
                }}
            </g>
            <text x="14" y="272" className="viewer-scale-label">RDKit conformer · ball-and-stick</text>
        </svg>
    </div>;
}

def:pub PipelineStepper(is_running: bool, has_results: bool) -> JsxElement {
    return <section className="panel pipeline-panel" aria-label="Discovery pipeline status">
        <div className="progress-heading">
            <div className="progress-copy">
                <p className="eyebrow">REFINEMENT STATUS</p>
                <p className="pipeline-caption">{("Building 3D conformers and calculating RDKit descriptors…" if is_running else ("Candidate models generated · RDKit screen complete" if has_results else "Ready for your seed molecule"))}</p>
            </div>
            <span className={"progress-state " + ("progress-state-running" if is_running else ("progress-state-complete" if has_results else ""))}>
                {( "REFINING" if is_running else ("COMPLETE" if has_results else "READY"))}
            </span>
        </div>
        <div className={"progress-track " + ("progress-track-running" if is_running else "")} aria-hidden="true">
            <div className={"progress-fill " + ("progress-fill-running" if is_running else ("progress-fill-complete" if has_results else "progress-fill-idle"))} />
        </div>
        <p className="pipeline-footnote">Target lookup, PDB retrieval, and AutoDock Vina are not connected in this prototype.</p>
    </section>;
}

def:pub CandidateChain(candidates: list[CandidateView]) -> JsxElement {
    return <section className="panel chain-panel">
        <div className="section-heading">
            <div>
                <p className="eyebrow">MOLECULAR LINEAGE</p>
                <h2 className="section-title">Generation chain</h2>
                <p className="section-description">Interactive RDKit 3D conformers and descriptors; edits and proxy ranking are target-agnostic heuristics.</p>
            </div>
            <span className="count-pill">{str(len(candidates))} GENERATIONS</span>
        </div>
        <div className="chain-scroll">
            <div className="generation-chain">
                {for (index, candidate) in enumerate(candidates) {
                    <div key={str(candidate.generation)} className="generation-item">
                        <article className="candidate-card">
                            <div className="candidate-card-top">
                                <div className="generation-label"><span className="generation-index">{str(candidate.generation)}</span><span>GENERATION {str(candidate.generation)}</span></div>
                                <span className={"screen-badge " + ("screen-badge-pass" if candidate.lipinski_pass else "screen-badge-fail")}>
                                    <HugeiconsIcon icon={CheckmarkCircle01Icon if candidate.lipinski_pass else Alert01Icon} strokeWidth={2} className="size-3.5" />
                                    {("LIPINSKI PASS" if candidate.lipinski_pass else "LIPINSKI FAIL")}
                                </span>
                            </div>
                            <MoleculeViewer atoms={candidate.atoms} bonds={candidate.bonds} generation={candidate.generation} instance_id={"chain-" + str(candidate.generation)} className="candidate-molecule-viewer" />
                            <div className="candidate-stats">
                                <div className="stat-chip"><span>MolWt</span><strong>{str(candidate.mol_weight)}</strong></div>
                                <div className="stat-chip"><span>LogP</span><strong>{str(candidate.logp)}</strong></div>
                                <div className="stat-chip"><span>Proxy score</span><strong>{str(candidate.proxy_score)}</strong></div>
                            </div>
                            <div className="candidate-edit"><span className="eyebrow">EDIT HYPOTHESIS</span><p>{candidate.mutation_applied}</p></div>
                            <div className="candidate-smiles"><span className="eyebrow">SMILES</span><code>{candidate.smiles}</code></div>
                            <p className={"screening-note " + ("note-pass" if candidate.lipinski_pass else "note-fail")}>
                                <HugeiconsIcon icon={CheckmarkCircle01Icon if candidate.lipinski_pass else Alert01Icon} strokeWidth={2} className="size-3.5 shrink-0" />
                                {candidate.failure_reason}
                            </p>
                        </article>
                        {if index < len(candidates) - 1 {
                            <div className="generation-connector" aria-label="Mutation between generations">
                                <div className="connector-arrow"><span /> <span className="connector-arrow-symbol">→</span></div>
                                <p className="connector-label">{candidates[index + 1].mutation_applied}</p>
                                <p className="connector-reason">Prior screen: {candidate.failure_reason}</p>
                            </div>
                        }}
                    </div>
                }}
            </div>
        </div>
        <div className="chain-legend"><span><span className="legend-dot legend-pass" />Rule-of-Five estimate passed</span><span><span className="legend-dot legend-review" />Review / threshold exceeded</span><span className="legend-disclaimer">Descriptors use RDKit; ranking remains heuristic.</span></div>
    </section>;
}

def:pub FinalResults(candidates: list[CandidateView], docking_status: str, scope_note: str) -> JsxElement {
    winner = candidates[0];
    for candidate in candidates {
        if candidate.proxy_score > winner.proxy_score { winner = candidate; }
    }

    return <aside className="results-column">
        <section className="panel winner-panel">
            <div className="section-heading winner-heading">
                <div><p className="eyebrow">TOP PROXY CANDIDATE</p><h2 className="section-title">Final results</h2></div>
                <span className="winner-crown">★</span>
            </div>
            <MoleculeViewer atoms={winner.atoms} bonds={winner.bonds} generation={winner.generation} instance_id="winner" className="winner-molecule-viewer" />
            <div className="winner-generation"><span>GENERATION {str(winner.generation)}</span><span className={"screen-badge " + ("screen-badge-pass" if winner.lipinski_pass else "screen-badge-fail")}>{("SCREEN PASS" if winner.lipinski_pass else "SCREEN FAIL")}</span></div>
            <p className="winner-smiles">{winner.smiles}</p>
            <div className="winner-proxy"><span>Proxy score</span><strong>{str(winner.proxy_score)}</strong></div>
            <div className="affinity-card">
                <p className="eyebrow">BINDING AFFINITY</p>
                <p className="affinity-value">Not available</p>
                <p className="affinity-unit">kcal/mol · {docking_status}</p>
                <div className="pdb-line"><span>Target structure</span><strong>PDB not fetched</strong></div>
            </div>
        </section>
        <section className="scope-card">
            <div className="scope-card-title"><span className="scope-mark">i</span><p>Scope of this run</p></div>
            <p>{scope_note}</p>
        </section>
    </aside>;
}

def:pub DiscoveryWorkspace() -> JsxElement {
    has target_name: str = "EGFR";
    has disease_context: str = "Non-small cell lung cancer";
    has pathway: str = "EGFR / MAPK signaling";
    has seed_smiles: str = "CC(C)(C)c1ccc(-c2ccccc2)cc1";
    has candidates: list[CandidateView] = [];
    has graph: JacGraphView | None = None;
    has run_target: str = "";
    has docking_status: str = "";
    has scope_note: str = "";
    has loading: bool = False;
    has error_message: str = "";

    def change_target(e: ChangeEvent) { target_name = e.target.value; }
    def change_disease(e: ChangeEvent) { disease_context = e.target.value; }
    def change_pathway(e: ChangeEvent) { pathway = e.target.value; }
    def change_seed(e: ChangeEvent) { seed_smiles = e.target.value; }
    async def handle_run -> None {
        loading = True;
        error_message = "";
        candidates = [];
        graph = None;
        run_target = "";
        try {
            outcome = await run_discovery(target_name, disease_context, seed_smiles);
            candidates = outcome.candidates;
            graph = outcome.graph;
            run_target = outcome.target_name;
            docking_status = outcome.docking_status;
            scope_note = outcome.scope_note;
        } except Exception {
            error_message = "The run could not be completed. Check the target name and try again.";
        }
        loading = False;
    }

    return <main className="app-shell">
        <header className="app-header">
            <div className="brand-lockup">
                <div className="brand-mark"><HugeiconsIcon icon={Atom01Icon} strokeWidth={1.8} className="size-5" /></div>
                <div><p className="brand-name">ASTERION <span>DISCOVERY</span></p><p className="brand-caption">Autonomous molecular research</p></div>
            </div>
            <div className="header-meta"><span className="live-dot" />RESEARCH WORKSPACE<span className="header-divider" />PROOF OF CONCEPT</div>
        </header>

        <div className="workspace">
            <section className="command-bar panel">
                <div className="command-intro">
                    <p className="eyebrow">MOLECULAR INTELLIGENCE</p>
                    <h1>Candidate refinement</h1>
                    <p className="command-subtitle">Explore a graph-backed, heuristic refinement demo, then inspect each candidate molecule.</p>
                </div>
                <div className="target-controls research-form">
                    <label className="target-input-wrap" htmlFor="target-name">
                        <span className="input-label">TARGET NAME</span>
                        <Input id="target-name" value={target_name} onChange={change_target} placeholder="EGFR, COVID-19 main protease" className="target-input" />
                    </label>
                    <label className="target-input-wrap" htmlFor="disease-context">
                        <span className="input-label">DISEASE CONTEXT</span>
                        <Input id="disease-context" value={disease_context} onChange={change_disease} className="target-input" />
                    </label>
                    <label className="target-input-wrap" htmlFor="pathway">
                        <span className="input-label">BIOLOGICAL PATHWAY</span>
                        <Input id="pathway" value={pathway} onChange={change_pathway} className="target-input" />
                    </label>
                    <label className="target-input-wrap seed-input-wrap" htmlFor="seed-smiles">
                        <span className="input-label">SEED SMILES</span>
                        <textarea id="seed-smiles" value={seed_smiles} onChange={change_seed} className="target-input seed-textarea" />
                    </label>
                    <p className="seed-note">RDKit generates a 3D conformer from the seed SMILES. Target and pathway are recorded for context; heuristic refinement is target-agnostic.</p>
                    <Button className="run-button" disabled={loading} onClick={handle_run}>
                        <HugeiconsIcon icon={SparklesIcon} strokeWidth={2} className="size-4" />
                        {("Running refinement…" if loading else "Run refinement demo")}
                    </Button>
                </div>
                <div className="command-foot"><span>Research prototype</span><span className="command-foot-note">RDKit descriptors · heuristic proxy</span></div>
                {error_message and <p role="alert" className="error-message">{error_message}</p>}
            </section>

            <PipelineStepper is_running={loading} has_results={len(candidates) > 0} />

            <div className="run-context">
                <div><span className="eyebrow">CURRENT TARGET</span><strong>{(run_target if len(candidates) > 0 else target_name)}</strong></div>
                <span className="context-tag">{("CANDIDATE CHAIN READY" if len(candidates) > 0 else ("GENERATING CANDIDATES" if loading else "READY TO RUN"))}</span>
            </div>

            <JacGraphPanel graph={graph} />

            {if len(candidates) == 0 {
                <section className="panel empty-state">
                    <div className="empty-orbit"><HugeiconsIcon icon={Atom01Icon} strokeWidth={1.3} className="size-8" /></div>
                    <p className="eyebrow">DISCOVERY CANVAS</p>
                    <h2>{("Generating your candidate chain" if loading else "Your candidate chain starts here")}</h2>
                    <p>{("RDKit is checking the demo scaffold and building heuristic variants." if loading else "Enter a target label to inspect an RDKit-rendered candidate chain from the demo scaffold. This prototype does not condition edits or ranking on the target.")}</p>
                    <div className="empty-state-meta"><span>01 · Validate SMILES</span><span>02 · Estimate descriptors</span><span>03 · Rank proxy scores</span></div>
                </section>
            }}

            {if len(candidates) > 0 {
                <div className="results-layout">
                    <CandidateChain candidates={candidates} />
                    <FinalResults candidates={candidates} docking_status={docking_status} scope_note={scope_note} />
                </div>
            }}

            <footer className="app-footer"><span>ASTERION DISCOVERY · RESEARCH PROTOTYPE</span><span>Heuristic candidate refinement · no clinical use</span></footer>
        </div>
    </main>;
}
