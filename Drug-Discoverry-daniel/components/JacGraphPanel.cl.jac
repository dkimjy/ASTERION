sv import from ..services.discovery { JacGraphNode, JacGraphView }

obj GraphPosition {
    has x: float;
    has y: float;
    has width: float;
    has height: float;
}

def _graph_position(graph_node: JacGraphNode) -> GraphPosition {
    if graph_node.node_type == "Root" {
        return GraphPosition(x=30.0, y=186.0, width=140.0, height=72.0);
    }
    if graph_node.node_type == "Target" {
        return GraphPosition(x=245.0, y=58.0, width=170.0, height=82.0);
    }
    return GraphPosition(x=245.0 + float(graph_node.generation) * 195.0, y=250.0, width=160.0, height=82.0);
}

def:pub JacGraphPanel(graph: JacGraphView | None) -> JsxElement {
    return <section className="panel jac-graph-panel" aria-label="Jac node and walker graph">
        <div className="jac-graph-heading">
            <div>
                <p className="eyebrow">JAC OBJECT-SPATIAL GRAPH</p>
                <h2 className="section-title">Run graph</h2>
                <p className="section-description">A separate view of the Jac nodes, typed edges, and graph-walker route.</p>
            </div>
            <span className="graph-mode-pill">{"LIVE RUN SNAPSHOT" if graph is not None else "SCHEMA PREVIEW"}</span>
        </div>
        {if graph is None {
            <div className="jac-schema-preview">
                <div className="schema-root"><span>ROOT</span><strong>Jac graph</strong></div>
                <div className="schema-branches">
                    <div className="schema-branch"><span className="schema-link-label">untyped attachment</span><div className="schema-node schema-target"><span>node</span><strong>Target</strong><small>name · disease context</small></div></div>
                    <div className="schema-branch"><span className="schema-link-label">untyped attachment</span><div className="schema-node schema-candidate"><span>node</span><strong>Candidate</strong><small>SMILES · descriptors</small></div></div>
                    <div className="schema-derived"><span>typed edge</span><strong>DerivedFrom</strong><small>Candidate → Candidate</small></div>
                </div>
                <div className="jac-walker-row jac-walker-idle">
                    <div className="walker-mark">W</div>
                    <div className="walker-copy"><strong>DiscoveryGraphWalker</strong><span>Ready · traverses the run graph after refinement</span></div>
                    <span className="walker-status">IDLE</span>
                </div>
            </div>
        } else {
            <div className="jac-graph-scroll">
                <svg className="jac-graph-svg" viewBox="0 0 1010 390" role="img" aria-label="Live Jac graph containing Root, Target, Candidate nodes, and DerivedFrom edges">
                    <defs>
                        <marker id="jac-graph-arrow-root" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto" markerUnits="strokeWidth"><path d="M0,0 L8,4 L0,8 z" className="graph-arrow-root" /></marker>
                        <marker id="jac-graph-arrow-derived" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto" markerUnits="strokeWidth"><path d="M0,0 L8,4 L0,8 z" className="graph-arrow-derived" /></marker>
                    </defs>
                    <g className="jac-graph-edges">
                        {for edge in graph.edges {
                            source_node: JacGraphNode | None = None;
                            target_node: JacGraphNode | None = None;
                            for candidate_node in graph.nodes {
                                if candidate_node.node_id == edge.source { source_node = candidate_node; }
                                if candidate_node.node_id == edge.target { target_node = candidate_node; }
                            }
                            if source_node is not None {
                                if target_node is not None {
                                    source_pos = _graph_position(source_node as JacGraphNode);
                                    target_pos = _graph_position(target_node as JacGraphNode);
                                    <g key={edge.source + "-" + edge.target}>
                                        <line x1={source_pos.x + source_pos.width} y1={source_pos.y + source_pos.height / 2.0} x2={target_pos.x} y2={target_pos.y + target_pos.height / 2.0} className={"jac-graph-edge " + ("jac-graph-edge-derived" if edge.edge_type == "DerivedFrom" else "jac-graph-edge-root")} markerEnd={"url(#jac-graph-arrow-derived)" if edge.edge_type == "DerivedFrom" else "url(#jac-graph-arrow-root)"} />
                                        <title>{edge.edge_type + ": " + edge.label}</title>
                                    </g>
                                }
                            }
                        }}
                    </g>
                    <g className="jac-graph-nodes">
                        {for node in graph.nodes {
                            pos = _graph_position(node);
                            <g key={node.node_id}>
                                <rect x={pos.x} y={pos.y} width={pos.width} height={pos.height} rx="12" className={"jac-graph-node " + ("jac-graph-node-root" if node.node_type == "Root" else ("jac-graph-node-target" if node.node_type == "Target" else "jac-graph-node-candidate"))} />
                                <text x={pos.x + 13.0} y={pos.y + 19.0} className="jac-graph-node-type">{node.node_type}</text>
                                <text x={pos.x + 13.0} y={pos.y + 43.0} className="jac-graph-node-label">{node.label}</text>
                                <text x={pos.x + 13.0} y={pos.y + 64.0} className="jac-graph-node-detail">{node.detail}</text>
                            </g>
                        }}
                    </g>
                </svg>
            </div>
            <div className="jac-graph-legend">
                <span><i className="graph-legend-root" />Untyped root attachment</span>
                <span><i className="graph-legend-derived" />Typed DerivedFrom edge</span>
            </div>
            <div className="jac-walker-row">
                <div className="walker-mark">W</div>
                <div className="walker-copy">
                    <strong>{graph.walker.name}</strong>
                    <span>{for (step_index, step) in enumerate(graph.walker.route) {<>{step}{" → " if step_index < len(graph.walker.route) - 1 else ""}</>}}</span>
                </div>
                <span className="walker-status">{graph.walker.status} · {str(graph.walker.visited_count)} VISITED</span>
            </div>
        }}
    </section>;
}
