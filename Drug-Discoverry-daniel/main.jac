import from services.discovery { run_discovery }

cl {
    import from .components.DiscoveryWorkspace { DiscoveryWorkspace }
    import ".styles/global.css";

    def:pub app() -> JsxElement {
        return <DiscoveryWorkspace />;
    }
}
