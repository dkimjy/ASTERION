obj GraphSnapshot {
    has phase: str = "idle";
    has target: str = "EGFR";
    has disease: str = "";
    has pathway: str = "";
    has trace: list[str] = [];
    has candidate_count: int = 0;
    has evidence_count: int = 0;
}

def _parse_graph_snapshot(raw: str) -> GraphSnapshot {
    parsed: any = JSON.parse(raw);
    return GraphSnapshot(phase=parsed["phase"] as str, target=parsed["target"] as str, disease=parsed["disease"] as str, pathway=parsed["pathway"] as str, trace=parsed["trace"] as list[str], candidate_count=parsed["candidate_count"] as int, evidence_count=parsed["evidence_count"] as int);
}

def:pub GraphLiveView() -> JsxElement {
    has graph_state: GraphSnapshot = GraphSnapshot();

    async can with entry {
        saved = localStorage.getItem("asterion-workflow");
        if saved { graph_state = _parse_graph_snapshot(saved as str); }
        setInterval(lambda {
            latest = localStorage.getItem("asterion-workflow");
            if latest { graph_state = _parse_graph_snapshot(latest as str); }
        }, 700);
    }

    phase_label: str = "WAITING FOR A RUN";
    phase_class: str = "graph-status-idle";
    if graph_state.phase == "running" {
        phase_label = "WALKER IN MOTION · GATHERING EVIDENCE";
        phase_class = "graph-status-running";
    } elif graph_state.phase == "complete" {
        phase_label = "TRAVERSAL COMPLETE · LIVE GRAPH SNAPSHOT";
        phase_class = "graph-status-complete";
    } elif graph_state.phase == "error" {
        phase_label = "RUN NEEDS INPUT REVIEW";
        phase_class = "graph-status-error";
    }

    return <section className="graph-embedded" aria-label="Live Jac graph traversal">
            <section className="graph-live-panel">
                <div className="graph-live-heading"><div><span className="eyebrow">JAC WALKER STREAM · LIVE</span><p className={"graph-status " + phase_class}><span className="live-dot" />{phase_label}</p></div></div>
                <svg className="jac-graph" viewBox="0 0 1040 510" role="img" aria-label="Jac nodes, typed edges and animated walker traversal">
                    <defs>
                        <marker id="graph-arrow" markerWidth="10" markerHeight="8" refX="8" refY="4" orient="auto"><path d="M0 0 L9 4 L0 8 Z" fill="#526c78" /></marker>
                        <filter id="walker-glow" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="4" result="blur" /><feMerge><feMergeNode in="blur" /><feMergeNode in="SourceGraphic" /></feMerge></filter>
                    </defs>
                    <path className="graph-edge" markerEnd="url(#graph-arrow)" d="M174 234 C219 211 235 188 273 174" />
                    <path className="graph-edge" markerEnd="url(#graph-arrow)" d="M391 152 C441 122 470 120 506 129" />
                    <path className="graph-edge" markerEnd="url(#graph-arrow)" d="M387 183 C444 227 469 279 510 315" />
                    <path className="graph-edge graph-edge-lineage" markerEnd="url(#graph-arrow)" d="M630 327 L693 327" />
                    <path className="graph-edge graph-edge-lineage" markerEnd="url(#graph-arrow)" d="M812 327 L873 327" />
                    <text className="graph-edge-label" x="416" y="110">HasEvidence</text><text className="graph-edge-label" x="421" y="267">StartsWith</text><text className="graph-edge-label" x="636" y="309">DerivedFrom</text><text className="graph-edge-label" x="824" y="309">DerivedFrom</text>
                    <g className="jac-node jac-root"><rect x="56" y="213" width="120" height="54" rx="15" /><text x="116" y="237" textAnchor="middle" className="node-kind">JAC ROOT</text><text x="116" y="253" textAnchor="middle" className="node-caption">entry point</text></g>
                    <g className="jac-node jac-target"><rect x="270" y="130" width="128" height="64" rx="15" /><text x="334" y="155" textAnchor="middle" className="node-kind">TARGET</text><text x="334" y="176" textAnchor="middle" className="node-caption">{graph_state.target or "Awaiting input"}</text></g>
                    <g className="jac-node jac-evidence"><rect x="504" y="94" width="132" height="66" rx="15" /><text x="570" y="120" textAnchor="middle" className="node-kind">EVIDENCE</text><text x="570" y="143" textAnchor="middle" className="node-caption">{str(graph_state.evidence_count)} KEGG / DGIdb</text></g>
                    <g className="jac-node jac-candidate"><rect x="504" y="294" width="132" height="66" rx="15" /><text x="570" y="320" textAnchor="middle" className="node-kind">SEED CANDIDATE</text><text x="570" y="343" textAnchor="middle" className="node-caption">generation 0</text></g>
                    <g className="jac-node jac-candidate"><rect x="693" y="294" width="120" height="66" rx="15" /><text x="753" y="320" textAnchor="middle" className="node-kind">CANDIDATE</text><text x="753" y="343" textAnchor="middle" className="node-caption">generations 1…</text></g>
                    <g className="jac-node jac-candidate"><rect x="873" y="294" width="120" height="66" rx="15" /><text x="933" y="320" textAnchor="middle" className="node-kind">RESULT</text><text x="933" y="343" textAnchor="middle" className="node-caption">{str(graph_state.candidate_count)} candidates</text></g>
                    {if graph_state.phase == "running" {<circle className="graph-walker" r="5"><animateMotion dur="1s" repeatCount="indefinite" path="M174 234 C219 211 235 188 273 174 C317 153 352 143 391 152 C441 122 470 120 506 129 C470 120 441 122 391 152 C387 183 444 227 469 279 510 315 L630 327 L693 327 L812 327 L873 327" /><animate attributeName="opacity" values="0;1;1;0" keyTimes="0;0.04;0.94;1" dur="1s" repeatCount="indefinite" /></circle>}}
                    <text className="walker-label" x="56" y="446">WALKER · REFINEMENTTRACE</text><text className="graph-hint" x="56" y="466">During a run, one walker follows typed edges in visit order. The trace lists its reported visits.</text>
                </svg>
            </section>
            <section className="graph-lower-grid">
                <article className="graph-info-card"><p className="eyebrow">CURRENT CONTEXT</p><h2>{graph_state.target or "No target yet"}</h2><dl><dt>Disease</dt><dd>{graph_state.disease or "Waiting for run"}</dd><dt>Pathway</dt><dd>{graph_state.pathway or "Waiting for run"}</dd><dt>Graph records</dt><dd>{str(graph_state.evidence_count)} evidence · {str(graph_state.candidate_count)} candidates</dd></dl></article>
                <article className="graph-info-card graph-trace-card"><p className="eyebrow">WALKER EVENT TRACE</p>{if len(graph_state.trace) == 0 {<p className="graph-empty-trace">Start a refinement run in the workspace. The walker will publish its node and edge visits here.</p>} else {<ol className="graph-event-list">{for (index, event) in enumerate(graph_state.trace) {<li key={str(index)}><span>{str(index + 1)}</span><code>{event}</code></li>}}</ol>}}</article>
            </section>
    </section>;
}
