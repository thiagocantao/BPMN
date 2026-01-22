(() => {
    const { createApp, ref, reactive, computed, onMounted } = Vue;

    const uid = (prefix = "X") => `${prefix}_${Date.now()}_${Math.floor(Math.random() * 1e9)}`;

    const DEFAULT_SIZES = {
        startEvent: { w: 36, h: 36, name: "Início" },
        endEvent: { w: 36, h: 36, name: "Fim" },
        task: { w: 160, h: 70, name: "Tarefa" },
        exclusiveGateway: { w: 56, h: 56, name: "Decisão" },
    };

    const centerOf = (n) => ({ x: n.x + n.w / 2, y: n.y + n.h / 2 });

    createApp({
        setup() {
            const modelId = window.__BPMN_MODEL_ID__ || 0;

            const saving = ref(false);
            const mode = ref("select");       // select | connect
            const addType = ref(null);        // quando estiver adicionando

            const modelName = ref("");

            const nodes = ref([]);
            const edges = ref([]);

            const selectedId = ref(null);

            // pan/zoom simples via viewBox (MVP)
            const view = reactive({ x: 0, y: 0, w: 1200, h: 700 });
            const viewBox = computed(() => `${view.x} ${view.y} ${view.w} ${view.h}`);

            const svgRef = ref(null);

            // drag
            const drag = reactive({
                active: false,
                nodeId: null,
                startMouse: { x: 0, y: 0 },
                startNode: { x: 0, y: 0 },
                moved: false,
                justDragged: false
            });

            // connect
            const connect = reactive({
                fromId: null,
                dragging: false
            });

            const connectPreview = reactive({
                show: false,
                x1: 0, y1: 0, x2: 0, y2: 0
            });

            const setMode = (m) => {
                mode.value = m;
                addType.value = null;
                resetConnect();
            };

            const beginAdd = (t) => {
                addType.value = t;
                mode.value = "select";
                resetConnect();
            };

            const getSvgPoint = (evt) => {
                const svg = svgRef.value;
                const pt = svg.createSVGPoint();
                pt.x = evt.clientX;
                pt.y = evt.clientY;
                const m = svg.getScreenCTM().inverse();
                const p = pt.matrixTransform(m);
                return { x: p.x, y: p.y };
            };

            const load = () => {
                PageMethods.GetModel(
                    modelId,
                    (dto) => {
                        modelName.value = dto.Name;

                        let parsed;
                        try {
                            parsed = JSON.parse(dto.ModelJson);
                        } catch {
                            parsed = null;
                        }

                        if (!parsed || !Array.isArray(parsed.nodes) || !Array.isArray(parsed.edges)) {
                            alert("JSON inválido no banco. Carregando vazio.");
                            nodes.value = [];
                            edges.value = [];
                            return;
                        }

                        // Normaliza
                        nodes.value = parsed.nodes.map(n => ({
                            id: String(n.id),
                            type: n.type,
                            name: n.name ?? "",
                            x: Number(n.x ?? 0),
                            y: Number(n.y ?? 0),
                            w: Number(n.w ?? 80),
                            h: Number(n.h ?? 50),
                            meta: n.meta ?? {}
                        }));

                        edges.value = parsed.edges.map(e => ({
                            id: String(e.id),
                            type: e.type ?? "sequenceFlow",
                            from: String(e.from),
                            to: String(e.to),
                            waypoints: Array.isArray(e.waypoints) ? e.waypoints : [],
                            meta: e.meta ?? {}
                        }));
                    },
                    (err) => {
                        console.error(err);
                        alert("Erro ao carregar modelo.");
                    }
                );
            };

            const buildJsonToSave = () => {
                // MVP: recalcula waypoints automáticos (reta entre centros)
                const nodeById = Object.fromEntries(nodes.value.map(n => [n.id, n]));
                const normalizedEdges = edges.value.map(e => {
                    const a = nodeById[e.from];
                    const b = nodeById[e.to];
                    let wps = e.waypoints;

                    if (!Array.isArray(wps) || wps.length === 0) {
                        if (a && b) {
                            const ca = centerOf(a);
                            const cb = centerOf(b);
                            wps = [{ x: ca.x, y: ca.y }, { x: cb.x, y: cb.y }];
                        } else {
                            wps = [];
                        }
                    }
                    return { ...e, waypoints: wps };
                });

                return {
                    schemaVersion: 1,
                    diagram: { id: "D1", name: modelName.value || "Processo" },
                    nodes: nodes.value,
                    edges: normalizedEdges
                };
            };

            const save = () => {
                saving.value = true;
                const payload = buildJsonToSave();
                const json = JSON.stringify(payload);

                PageMethods.SaveModel(
                    modelId,
                    modelName.value || "Processo",
                    json,
                    () => { saving.value = false; alert("Salvo com sucesso."); },
                    (err) => { console.error(err); saving.value = false; alert("Erro ao salvar."); }
                );
            };

            const findNode = (id) => nodes.value.find(n => n.id === id);

            const CONNECTOR_OFFSET = 4;

            const connectorPoint = (n) => ({
                x: n.x + n.w + CONNECTOR_OFFSET,
                y: n.y + n.h / 2
            });

            const resetConnect = () => {
                connect.fromId = null;
                connect.dragging = false;
                connectPreview.show = false;
                window.removeEventListener("mousemove", onConnectMove);
                window.removeEventListener("mouseup", onConnectCancel);
            };

            const edgePoints = (e) => {
                const from = findNode(e.from);
                const to = findNode(e.to);
                if (!from || !to) return "";

                // reta entre centros (MVP)
                const a = centerOf(from);
                const b = centerOf(to);
                return `${a.x},${a.y} ${b.x},${b.y}`;
            };

            const diamondPoints = (w, h) => {
                const cx = w / 2, cy = h / 2;
                return `${cx},0 ${w},${cy} ${cx},${h} 0,${cy}`;
            };

            const onCanvasMouseDown = (evt) => {
                // Inserir nó
                if (addType.value) {
                    const p = getSvgPoint(evt);
                    const t = addType.value;
                    const def = DEFAULT_SIZES[t] || { w: 100, h: 60, name: "Nó" };

                    const id = uid("N");
                    const node = {
                        id,
                        type: t,
                        name: def.name,
                        x: Math.round(p.x - def.w / 2),
                        y: Math.round(p.y - def.h / 2),
                        w: def.w,
                        h: def.h,
                        meta: {}
                    };

                    nodes.value.push(node);
                    selectedId.value = id;
                    addType.value = null;
                    return;
                }

                // Clique no vazio: deseleciona
                selectedId.value = null;
            };

            const onNodeDown = (evt, node) => {
                if (mode.value === "connect") {
                    // em connect, não inicia drag
                    return;
                }

                const p = getSvgPoint(evt);
                drag.active = true;
                drag.nodeId = node.id;
                drag.startMouse = { x: p.x, y: p.y };
                drag.startNode = { x: node.x, y: node.y };
                drag.moved = false;
                drag.justDragged = false;

                window.addEventListener("mousemove", onMouseMove);
                window.addEventListener("mouseup", onMouseUp);
            };

            const onMouseMove = (evt) => {
                if (!drag.active) return;
                if (evt.buttons === 0) {
                    onMouseUp();
                    return;
                }
                const p = getSvgPoint(evt);
                const dx = p.x - drag.startMouse.x;
                const dy = p.y - drag.startMouse.y;

                const n = findNode(drag.nodeId);
                if (!n) return;

                if (dx !== 0 || dy !== 0) {
                    drag.moved = true;
                }

                n.x = Math.round(drag.startNode.x + dx);
                n.y = Math.round(drag.startNode.y + dy);
            };

            const onMouseUp = () => {
                drag.active = false;
                drag.nodeId = null;
                drag.justDragged = drag.moved;
                drag.moved = false;

                window.removeEventListener("mousemove", onMouseMove);
                window.removeEventListener("mouseup", onMouseUp);
            };

            const onNodeClick = (node) => {
                if (drag.justDragged) {
                    drag.justDragged = false;
                    return;
                }

                const isSelected = selectedId.value === node.id;
                if (mode.value !== "connect") {
                    selectedId.value = isSelected ? null : node.id;
                    return;
                }

                selectedId.value = node.id;

                // Connect flow
                if (!connect.fromId) {
                    connect.fromId = node.id;
                    connectPreview.show = true;

                    const c = centerOf(node);
                    connectPreview.x1 = c.x;
                    connectPreview.y1 = c.y;
                    connectPreview.x2 = c.x;
                    connectPreview.y2 = c.y;

                    window.addEventListener("mousemove", onConnectMove);
                    window.addEventListener("mouseup", onConnectCancel);
                    return;
                }

                if (connect.fromId === node.id) return;

                const newEdge = {
                    id: uid("E"),
                    type: "sequenceFlow",
                    from: connect.fromId,
                    to: node.id,
                    waypoints: [],
                    meta: {}
                };

                edges.value.push(newEdge);

                resetConnect();
            };

            const startConnectFromMenu = (node) => {
                mode.value = "connect";
                selectedId.value = node.id;
                connect.fromId = node.id;
                connect.dragging = false;
                connectPreview.show = true;

                const c = centerOf(node);
                connectPreview.x1 = c.x;
                connectPreview.y1 = c.y;
                connectPreview.x2 = c.x;
                connectPreview.y2 = c.y;

                window.addEventListener("mousemove", onConnectMove);
                window.addEventListener("mouseup", onConnectCancel);
            };

            const startConnectorDrag = (node) => {
                selectedId.value = node.id;
                connect.fromId = node.id;
                connect.dragging = true;
                connectPreview.show = true;

                const p = connectorPoint(node);
                connectPreview.x1 = p.x;
                connectPreview.y1 = p.y;
                connectPreview.x2 = p.x;
                connectPreview.y2 = p.y;

                window.addEventListener("mousemove", onConnectMove);
                window.addEventListener("mouseup", onConnectCancel);
            };

            const onConnectCancel = () => {
                if (!connectPreview.show) return;
                resetConnect();
            };

            const onNodeConnectDrop = (node) => {
                if (!connect.dragging || !connect.fromId) return;
                if (connect.fromId === node.id) return;

                const newEdge = {
                    id: uid("E"),
                    type: "sequenceFlow",
                    from: connect.fromId,
                    to: node.id,
                    waypoints: [],
                    meta: {}
                };

                edges.value.push(newEdge);
                resetConnect();
            };

            const onConnectMove = (evt) => {
                if (!connectPreview.show) return;
                const p = getSvgPoint(evt);
                connectPreview.x2 = p.x;
                connectPreview.y2 = p.y;
            };

            const selectEdge = (edgeId) => {
                selectedId.value = edgeId;
            };

            const deleteSelected = () => {
                if (!selectedId.value) return;

                const id = selectedId.value;

                // se for node, remove edges dependentes
                const node = findNode(id);
                if (node) {
                    edges.value = edges.value.filter(e => e.from !== id && e.to !== id);
                    nodes.value = nodes.value.filter(n => n.id !== id);
                    selectedId.value = null;
                    return;
                }

                // se for edge
                const edgeIndex = edges.value.findIndex(e => e.id === id);
                if (edgeIndex >= 0) {
                    edges.value.splice(edgeIndex, 1);
                    selectedId.value = null;
                }
            };

            onMounted(() => {
                load();
            });

            return {
                saving,
                mode,
                setMode,
                beginAdd,
                addType,
                modelName,

                nodes,
                edges,
                selectedId,

                viewBox,
                svgRef,
                connectPreview,

                edgePoints,
                diamondPoints,
                connectorPoint,
                connectorOffset: CONNECTOR_OFFSET,


                onCanvasMouseDown,
                onNodeDown,
                onNodeClick,
                onNodeConnectDrop,
                startConnectFromMenu,
                startConnectorDrag,
                selectEdge,

                save,
                deleteSelected
            };
        }
    }).mount("#bpmnApp");
})();
