import from ...lib.utils { cn }

def:pub Skeleton(props: any) -> JsxElement {
    attrs: dict[str, any] = {** props};
    return
        <div
            {**attrs}
            data-slot="skeleton"
            className={cn("bg-muted rounded-none animate-pulse", props["className"])}
        />;
}
