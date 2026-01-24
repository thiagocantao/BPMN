(() => {
    const { createApp, ref, reactive, computed, onMounted, nextTick, watch } = Vue;

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
            const sidebarMode = ref("edit");
            const aiPrompt = ref("");
            const aiPromptRef = ref(null);

            const nodes = ref([]);
            const edges = ref([]);

            const selectedId = ref(null);
            const selectedIds = ref([]);

            // pan/zoom simples via viewBox (MVP)
            const view = reactive({ x: 0, y: 0, w: 1200, h: 700 });
            const viewBox = computed(() => `${view.x} ${view.y} ${view.w} ${view.h}`);
            const isShiftPressed = ref(false);

            const svgRef = ref(null);
            const infoEditorRef = ref(null);
            const nameInputRef = ref(null);

            const pan = reactive({
                active: false,
                startMouse: { x: 0, y: 0 },
                startView: { x: 0, y: 0 },
                scale: { x: 1, y: 1 }
            });

            const selection = reactive({
                active: false,
                start: { x: 0, y: 0 },
                end: { x: 0, y: 0 }
            });

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


            const aiGenerating = ref(false);
            const aiSteps = [
                "Pensando...",
                "Carregando informações...",
                "Processando os dados...",
                "Gerando o gráfico..."
            ];
            const aiStepIndex = ref(0);
            const aiStepMessage = computed(() => aiSteps[aiStepIndex.value]);
            let aiStepTimer = null;

            const resizeAiPrompt = () => {
                const el = aiPromptRef.value;
                if (!el) return;
                const maxHeight = 300;
                el.style.height = "auto";
                const nextHeight = Math.min(el.scrollHeight, maxHeight);
                el.style.height = `${nextHeight}px`;
                el.style.overflowY = el.scrollHeight > maxHeight ? "auto" : "hidden";
            };

            const sendAiPrompt = () => {
                const prompt = (aiPrompt.value || "").trim();
                if (!prompt) return;

                aiGenerating.value = true;

                // envia também o JSON atual para permitir ajustes incrementais
                const current = JSON.stringify(buildJsonToSave());

                PageMethods.GenerateFromAi(
                    prompt,
                    current,
                    (res) => {
                        aiGenerating.value = false;

                        let parsed;
                        try {
                            parsed = JSON.parse(res.ModelJson);
                        } catch (e) {
                            console.error("AI returned invalid JSON:", res);
                            alert("A IA retornou um JSON inválido. Veja o console.");
                            return;
                        }

                        if (!parsed || !Array.isArray(parsed.nodes) || !Array.isArray(parsed.edges)) {
                            alert("A IA retornou um JSON sem nodes/edges.");
                            return;
                        }

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
                            type: e.type || "sequenceFlow",
                            from: String(e.from),
                            to: String(e.to),
                            waypoints: Array.isArray(e.waypoints) ? e.waypoints : [],
                            meta: e.meta ?? {}
                        }));

                        // opcional: centraliza a view
                        view.x = 0; view.y = 0;
                        // limpa campo
                        aiPrompt.value = "";
                        nextTick(resizeAiPrompt);
                        sidebarMode.value = "edit";
                    },
                    (err) => {
                        aiGenerating.value = false;
                        console.error(err);
                        alert((err && err.get_message) ? err.get_message() : "Erro ao chamar IA.");
                    }
                );
            };

            watch(aiGenerating, (active) => {
                if (active) {
                    aiStepIndex.value = 0;
                    if (aiStepTimer) clearInterval(aiStepTimer);
                    aiStepTimer = setInterval(() => {
                        aiStepIndex.value = (aiStepIndex.value + 1) % aiSteps.length;
                    }, 1400);
                    nextTick(resizeAiPrompt);
                } else if (aiStepTimer) {
                    clearInterval(aiStepTimer);
                    aiStepTimer = null;
                }
            });


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
            const bringNodeToFront = (id) => {
                const index = nodes.value.findIndex(n => n.id === id);
                if (index === -1 || index === nodes.value.length - 1) return;
                const [node] = nodes.value.splice(index, 1);
                nodes.value.push(node);
            };

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

            const resetSelection = () => {
                selection.active = false;
                window.removeEventListener("mousemove", onSelectionMove);
                window.removeEventListener("mouseup", onSelectionEnd);
            };

            const resetPan = () => {
                pan.active = false;
                window.removeEventListener("mousemove", onPanMove);
                window.removeEventListener("mouseup", onPanEnd);
            };

            const normalizeRect = (a, b) => {
                const x = Math.min(a.x, b.x);
                const y = Math.min(a.y, b.y);
                return {
                    x,
                    y,
                    w: Math.abs(a.x - b.x),
                    h: Math.abs(a.y - b.y)
                };
            };

            const selectionRect = computed(() => normalizeRect(selection.start, selection.end));

            const isNodeSelected = (nodeId) => {
                return selectedId.value === nodeId || selectedIds.value.includes(nodeId);
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

            const edgeMidpoint = (e) => {
                const from = findNode(e.from);
                const to = findNode(e.to);
                if (!from || !to) {
                    return { x: 0, y: 0, valid: false };
                }

                const a = centerOf(from);
                const b = centerOf(to);
                return {
                    x: (a.x + b.x) / 2,
                    y: (a.y + b.y) / 2,
                    valid: true
                };
            };

            const diamondPoints = (w, h) => {
                const cx = w / 2, cy = h / 2;
                return `${cx},0 ${w},${cy} ${cx},${h} 0,${cy}`;
            };

            const onCanvasMouseDown = (evt) => {
                if (connectPreview.show) {
                    resetConnect();
                    return;
                }

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
                    bringNodeToFront(id);
                    addType.value = null;
                    return;
                }

                if (isShiftPressed.value) {
                    const p = getSvgPoint(evt);
                    selection.active = true;
                    selection.start = { x: p.x, y: p.y };
                    selection.end = { x: p.x, y: p.y };
                    window.addEventListener("mousemove", onSelectionMove);
                    window.addEventListener("mouseup", onSelectionEnd);
                    return;
                }

                const svg = svgRef.value;
                pan.active = true;
                pan.startMouse = { x: evt.clientX, y: evt.clientY };
                pan.startView = { x: view.x, y: view.y };
                if (svg) {
                    pan.scale = {
                        x: view.w / svg.clientWidth,
                        y: view.h / svg.clientHeight
                    };
                } else {
                    pan.scale = { x: 1, y: 1 };
                }
                window.addEventListener("mousemove", onPanMove);
                window.addEventListener("mouseup", onPanEnd);

                // Clique no vazio: deseleciona
                selectedId.value = null;
                selectedIds.value = [];
            };

            const onNodeDown = (evt, node) => {
                if (isShiftPressed.value) {
                    return;
                }

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

                if (isShiftPressed.value) {
                    if (selectedIds.value.includes(node.id)) {
                        selectedIds.value = selectedIds.value.filter(id => id !== node.id);
                    } else {
                        selectedIds.value = [...selectedIds.value, node.id];
                    }
                    selectedId.value = null;
                    return;
                }

                const isSelected = isNodeSelected(node.id);
                if (mode.value !== "connect") {
                    selectedId.value = isSelected ? null : node.id;
                    selectedIds.value = isSelected ? [] : [node.id];
                    if (!isSelected) {
                        bringNodeToFront(node.id);
                    }
                    return;
                }

                selectedId.value = node.id;
                selectedIds.value = [node.id];
                bringNodeToFront(node.id);

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
                bringNodeToFront(node.id);
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
                bringNodeToFront(node.id);
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
                selectedIds.value = [];
            };

            const nameEditor = reactive({
                nodeId: null,
                value: ""
            });

            const isEditingName = (node) => nameEditor.nodeId === node.id;

            const beginNameEdit = (node) => {
                nameEditor.nodeId = node.id;
                nameEditor.value = node.name ?? "";
                nextTick(() => {
                    if (nameInputRef.value) {
                        nameInputRef.value.focus();
                        nameInputRef.value.select();
                    }
                });
            };

            const saveNameEdit = () => {
                if (!nameEditor.nodeId) return;
                const node = findNode(nameEditor.nodeId);
                if (node) {
                    node.name = nameEditor.value;
                }
                nameEditor.nodeId = null;
                nameEditor.value = "";
            };

            const cancelNameEdit = () => {
                nameEditor.nodeId = null;
                nameEditor.value = "";
            };

            const infoEditor = reactive({
                show: false,
                nodeId: null,
                content: ""
            });

            const infoViewer = reactive({
                show: false,
                nodeId: null,
                content: ""
            });

            const openInfoEditor = (node) => {
                selectedId.value = node.id;
                infoViewer.show = false;
                infoEditor.nodeId = node.id;
                infoEditor.content = node.meta?.infoHtml ?? "";
                infoEditor.show = true;
                nextTick(() => {
                    if (infoEditorRef.value) {
                        infoEditorRef.value.innerHTML = infoEditor.content;
                        infoEditorRef.value.focus();
                    }
                });
            };

            const closeInfoEditor = () => {
                infoEditor.show = false;
                infoEditor.nodeId = null;
                infoEditor.content = "";
            };

            const onEditorInput = () => {
                infoEditor.content = infoEditorRef.value ? infoEditorRef.value.innerHTML : "";
            };

            const formatInfoEditor = (command) => {
                if (!infoEditorRef.value) return;
                infoEditorRef.value.focus();
                if (command === "createLink") {
                    const url = window.prompt("Informe o link:");
                    if (url) {
                        document.execCommand(command, false, url);
                    }
                    return;
                }
                document.execCommand(command, false, null);
            };

            const saveInfoEditor = () => {
                if (!infoEditor.nodeId) return;
                const node = findNode(infoEditor.nodeId);
                if (!node) return;
                const html = infoEditorRef.value ? infoEditorRef.value.innerHTML : infoEditor.content;
                node.meta = {
                    ...(node.meta ?? {}),
                    infoHtml: html
                };
                closeInfoEditor();
            };

            const openInfoViewer = (node) => {
                selectedId.value = node.id;
                infoEditor.show = false;
                infoViewer.nodeId = node.id;
                infoViewer.content = node.meta?.infoHtml ?? "";
                infoViewer.show = true;
            };

            const closeInfoViewer = () => {
                infoViewer.show = false;
                infoViewer.nodeId = null;
                infoViewer.content = "";
            };

            const deleteSelected = () => {
                if (selectedIds.value.length > 0) {
                    const ids = new Set(selectedIds.value);
                    edges.value = edges.value.filter(e => !ids.has(e.from) && !ids.has(e.to));
                    nodes.value = nodes.value.filter(n => !ids.has(n.id));
                    selectedId.value = null;
                    selectedIds.value = [];
                    return;
                }

                if (!selectedId.value) return;

                const id = selectedId.value;

                // se for node, remove edges dependentes
                const node = findNode(id);
                if (node) {
                    edges.value = edges.value.filter(e => e.from !== id && e.to !== id);
                    nodes.value = nodes.value.filter(n => n.id !== id);
                    selectedId.value = null;
                    selectedIds.value = [];
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
                nextTick(resizeAiPrompt);
                const updateShiftState = (event) => {
                    isShiftPressed.value = event.shiftKey;
                };
                window.addEventListener("keydown", updateShiftState);
                window.addEventListener("keyup", updateShiftState);
            });

            const onPanMove = (evt) => {
                if (!pan.active) return;
                if (evt.buttons === 0) {
                    onPanEnd();
                    return;
                }
                const dx = evt.clientX - pan.startMouse.x;
                const dy = evt.clientY - pan.startMouse.y;
                view.x = Math.round(pan.startView.x + dx * pan.scale.x);
                view.y = Math.round(pan.startView.y + dy * pan.scale.y);
            };

            const onPanEnd = () => {
                if (!pan.active) return;
                resetPan();
            };

            const onSelectionMove = (evt) => {
                if (!selection.active) return;
                const p = getSvgPoint(evt);
                selection.end = { x: p.x, y: p.y };
            };

            const onSelectionEnd = () => {
                if (!selection.active) return;
                const { x, y, w, h } = selectionRect.value;
                const x2 = x + w;
                const y2 = y + h;
                const selected = nodes.value
                    .filter(n => n.x <= x2 && n.x + n.w >= x && n.y <= y2 && n.y + n.h >= y)
                    .map(n => n.id);
                selectedIds.value = selected;
                selectedId.value = selected.length === 1 ? selected[0] : null;
                resetSelection();
            };

            return {
                saving,
                mode,
                setMode,
                beginAdd,
                addType,
                modelName,
                sidebarMode,
                aiPrompt,
                aiPromptRef,
                aiGenerating,
                aiStepMessage,

                nodes,
                edges,
                selectedId,
                selectedIds,

                viewBox,
                isShiftPressed,
                svgRef,
                connectPreview,
                pan,
                selection,
                selectionRect,
                isNodeSelected,

                edgePoints,
                edgeMidpoint,
                diamondPoints,
                connectorPoint,
                connectorOffset: CONNECTOR_OFFSET,

                nameEditor,
                nameInputRef,
                isEditingName,

                infoEditor,
                infoViewer,
                infoEditorRef,


                onCanvasMouseDown,
                onNodeDown,
                onNodeClick,
                onNodeConnectDrop,
                startConnectFromMenu,
                startConnectorDrag,
                selectEdge,
                beginNameEdit,
                saveNameEdit,
                cancelNameEdit,
                openInfoEditor,
                closeInfoEditor,
                onEditorInput,
                formatInfoEditor,
                saveInfoEditor,
                openInfoViewer,
                closeInfoViewer,

                save,
                deleteSelected,
                sendAiPrompt,
                resizeAiPrompt
            };
        }
    }).mount("#bpmnApp");
})();
