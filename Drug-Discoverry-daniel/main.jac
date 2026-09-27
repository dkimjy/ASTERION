import from services.discovery { run_discovery }

cl {
    import from .components.DiscoveryWorkspace { DiscoveryWorkspace }
    import ".styles/global.css";
    import from "@jac/runtime" { Router, Routes, Route }

    def:pub app() -> JsxElement {
        return <Router><Routes><Route path="/" element={<DiscoveryWorkspace />} /></Routes></Router>;
    }
}
