(() => {
    const { createApp, ref, reactive, computed, onMounted, nextTick, watch } = Vue;

    const uid = (prefix = "X") => `${prefix}_${Date.now()}_${Math.floor(Math.random() * 1e9)}`;

    const DEFAULT_SIZES = {
        startEvent: { w: 36, h: 36, name: "Início" },
        endEvent: { w: 36, h: 36, name: "Fim" },
        intermediateThrowEvent: { w: 36, h: 36, name: "Evento intermediário" },
        intermediateCatchEvent: { w: 36, h: 36, name: "Evento intermediário" },
        boundaryEvent: { w: 36, h: 36, name: "Evento de borda" },
        task: { w: 160, h: 70, name: "Tarefa" },
        userTask: { w: 160, h: 70, name: "Tarefa do usuário" },
        serviceTask: { w: 160, h: 70, name: "Tarefa de serviço" },
        scriptTask: { w: 160, h: 70, name: "Tarefa de script" },
        businessRuleTask: { w: 160, h: 70, name: "Regra de negócio" },
        manualTask: { w: 160, h: 70, name: "Tarefa manual" },
        sendTask: { w: 160, h: 70, name: "Enviar" },
        receiveTask: { w: 160, h: 70, name: "Receber" },
        callActivity: { w: 180, h: 90, name: "Chamada" },
        subProcess: { w: 200, h: 110, name: "Subprocesso" },
        transaction: { w: 200, h: 110, name: "Transação" },
        eventSubProcess: { w: 200, h: 110, name: "Subprocesso de evento" },
        adHocSubProcess: { w: 200, h: 110, name: "Subprocesso ad hoc" },
        exclusiveGateway: { w: 56, h: 56, name: "Decisão" },
        inclusiveGateway: { w: 56, h: 56, name: "Gateway inclusivo" },
        parallelGateway: { w: 56, h: 56, name: "Gateway paralelo" },
        eventBasedGateway: { w: 56, h: 56, name: "Gateway baseado em evento" },
        complexGateway: { w: 56, h: 56, name: "Gateway complexo" },
        dataObjectReference: { w: 36, h: 50, name: "Objeto de dados" },
        dataStoreReference: { w: 50, h: 50, name: "Repositório de dados" },
        dataInput: { w: 36, h: 50, name: "Entrada de dados" },
        dataOutput: { w: 36, h: 50, name: "Saída de dados" },
        textAnnotation: { w: 120, h: 60, name: "" },
        group: { w: 240, h: 160, name: "" },
        participant: { w: 600, h: 250, name: "Participante" },
        lane: { w: 600, h: 120, name: "Raia" }
    };

    const TYPE_TO_BPMN = {
        startEvent: "bpmn:StartEvent",
        endEvent: "bpmn:EndEvent",
        intermediateThrowEvent: "bpmn:IntermediateThrowEvent",
        intermediateCatchEvent: "bpmn:IntermediateCatchEvent",
        boundaryEvent: "bpmn:BoundaryEvent",
        task: "bpmn:Task",
        userTask: "bpmn:UserTask",
        serviceTask: "bpmn:ServiceTask",
        scriptTask: "bpmn:ScriptTask",
        businessRuleTask: "bpmn:BusinessRuleTask",
        manualTask: "bpmn:ManualTask",
        sendTask: "bpmn:SendTask",
        receiveTask: "bpmn:ReceiveTask",
        callActivity: "bpmn:CallActivity",
        subProcess: "bpmn:SubProcess",
        transaction: "bpmn:Transaction",
        eventSubProcess: "bpmn:SubProcess",
        adHocSubProcess: "bpmn:AdHocSubProcess",
        exclusiveGateway: "bpmn:ExclusiveGateway",
        inclusiveGateway: "bpmn:InclusiveGateway",
        parallelGateway: "bpmn:ParallelGateway",
        eventBasedGateway: "bpmn:EventBasedGateway",
        complexGateway: "bpmn:ComplexGateway",
        dataObjectReference: "bpmn:DataObjectReference",
        dataStoreReference: "bpmn:DataStoreReference",
        dataInput: "bpmn:DataInput",
        dataOutput: "bpmn:DataOutput",
        textAnnotation: "bpmn:TextAnnotation",
        group: "bpmn:Group",
        participant: "bpmn:Participant",
        lane: "bpmn:Lane"
    };

    const EMPTY_BPMN_XML = `<?xml version="1.0" encoding="UTF-8"?>
<bpmn:definitions xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xmlns:bpmn="http://www.omg.org/spec/BPMN/20100524/MODEL"
  xmlns:bpmndi="http://www.omg.org/spec/BPMN/20100524/DI"
  xmlns:dc="http://www.omg.org/spec/DD/20100524/DC"
  id="Definitions_1" targetNamespace="http://bpmn.io/schema/bpmn">
  <bpmn:process id="Process_1" isExecutable="false" />
  <bpmndi:BPMNDiagram id="BPMNDiagram_1">
    <bpmndi:BPMNPlane id="BPMNPlane_1" bpmnElement="Process_1" />
  </bpmndi:BPMNDiagram>
</bpmn:definitions>`;

    const ensureAttrs = (businessObject) => {
        if (!businessObject.$attrs) {
            businessObject.$attrs = {};
        }
        return businessObject.$attrs;
    };

    createApp({
        setup() {
            const modelId = window.__BPMN_MODEL_ID__ || 0;

            const saving = ref(false);
            const mode = ref("select");
            const addType = ref(null);

            const modelName = ref("");
            const sidebarMode = ref("edit");
            const aiPrompt = ref("");
            const aiPromptRef = ref(null);

            const modelerRef = ref(null);
            const bpmnCanvasRef = ref(null);

            const selectedId = ref(null);
            const selectedIds = ref([]);
            const selectedElement = ref(null);

            const infoEditorRef = ref(null);

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

            const infoEditor = reactive({
                show: false,
                elementId: null,
                content: ""
            });

            const infoViewer = reactive({
                show: false,
                elementId: null,
                content: ""
            });

            const canEditSelectedInfo = computed(() => {
                const element = selectedElement.value;
                return Boolean(element && !element.waypoints && !element.isRoot);
            });

            const openInfoEditor = (element) => {
                if (!element) return;
                selectedId.value = element.id;
                infoViewer.show = false;
                infoEditor.elementId = element.id;
                infoEditor.content = element.businessObject?.$attrs?.infoHtml ?? "";
                infoEditor.show = true;
                nextTick(() => {
                    if (infoEditorRef.value) {
                        infoEditorRef.value.innerHTML = infoEditor.content;
                        infoEditorRef.value.focus();
                    }
                });
            };

            const openInfoEditorFromSelection = () => {
                if (!canEditSelectedInfo.value) return;
                openInfoEditor(selectedElement.value);
            };

            const closeInfoEditor = () => {
                infoEditor.show = false;
                infoEditor.elementId = null;
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
                const modeler = modelerRef.value;
                if (!modeler || !infoEditor.elementId) return;
                const elementRegistry = modeler.get("elementRegistry");
                const element = elementRegistry.get(infoEditor.elementId);
                if (!element) return;
                const html = infoEditorRef.value ? infoEditorRef.value.innerHTML : infoEditor.content;
                const attrs = ensureAttrs(element.businessObject);
                attrs.infoHtml = html;
                closeInfoEditor();
            };

            const openInfoViewer = (element) => {
                if (!element) return;
                selectedId.value = element.id;
                infoEditor.show = false;
                infoViewer.elementId = element.id;
                infoViewer.content = element.businessObject?.$attrs?.infoHtml ?? "";
                infoViewer.show = true;
            };

            const openInfoViewerFromSelection = () => {
                if (!canEditSelectedInfo.value) return;
                openInfoViewer(selectedElement.value);
            };

            const createInfoContextPadModule = () => {
                const InfoContextPadProvider = function (contextPad) {
                    this.getContextPadEntries = (element) => {
                        if (!element || element.waypoints || element.isRoot) return {};

                        return {
                            "edit-info": {
                                group: "edit",
                                className: "context-pad-icon context-pad-icon--edit",
                                title: "Editar informações",
                                action: {
                                    click: (event, target) => {
                                        openInfoEditor(target);
                                    }
                                }
                            },
                            "view-info": {
                                group: "edit",
                                className: "context-pad-icon context-pad-icon--view",
                                title: "Visualizar informações",
                                action: {
                                    click: (event, target) => {
                                        openInfoViewer(target);
                                    }
                                }
                            }
                        };
                    };
                };

                InfoContextPadProvider.$inject = ["contextPad"];

                return {
                    __init__: ["infoContextPadProvider"],
                    infoContextPadProvider: ["type", InfoContextPadProvider]
                };
            };

            const closeInfoViewer = () => {
                infoViewer.show = false;
                infoViewer.elementId = null;
                infoViewer.content = "";
            };

            const getCurrentXml = async () => {
                const modeler = modelerRef.value;
                if (!modeler) return EMPTY_BPMN_XML;
                try {
                    const result = await modeler.saveXML({ format: true });
                    return result?.xml || EMPTY_BPMN_XML;
                } catch (err) {
                    console.error(err);
                    return EMPTY_BPMN_XML;
                }
            };

            const load = () => {
                PageMethods.GetModel(
                    modelId,
                    (dto) => {
                        modelName.value = dto.Name;

                        const xml = dto.ModelXml || EMPTY_BPMN_XML;
                        modelerRef.value.importXML(xml)
                            .then(() => {
                                modelerRef.value.get("canvas").zoom("fit-viewport", "auto");
                            })
                            .catch((err) => {
                                console.error(err);
                                alert("XML inválido no banco. Carregando vazio.");
                                modelerRef.value.importXML(EMPTY_BPMN_XML).then(() => {
                                    modelerRef.value.get("canvas").zoom("fit-viewport", "auto");
                                });
                            });
                    },
                    (err) => {
                        console.error(err);
                        alert("Erro ao carregar modelo.");
                    }
                );
            };

            const save = async () => {
                saving.value = true;
                const xml = await getCurrentXml();

                PageMethods.SaveModel(
                    modelId,
                    modelName.value || "Processo",
                    xml,
                    () => { saving.value = false; alert("Salvo com sucesso."); },
                    (err) => { console.error(err); saving.value = false; alert("Erro ao salvar."); }
                );
            };

            const sendAiPrompt = async () => {
                const prompt = (aiPrompt.value || "").trim();
                if (!prompt) return;

                aiGenerating.value = true;

                const current = await getCurrentXml();

                PageMethods.GenerateFromAi(
                    prompt,
                    current,
                    (res) => {
                        aiGenerating.value = false;

                        const xml = res.ModelXml || "";
                        if (!xml) {
                            alert("A IA retornou um XML vazio.");
                            return;
                        }

                        modelerRef.value.importXML(xml)
                            .then(() => {
                                modelerRef.value.get("canvas").zoom("fit-viewport", "auto");
                            })
                            .catch((e) => {
                                console.error("AI returned invalid XML:", res);
                                alert("A IA retornou um XML inválido. Veja o console.");
                                console.error(e);
                            });

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

            const beginAdd = (type) => {
                addType.value = type;
                mode.value = "select";
                const modeler = modelerRef.value;
                if (!modeler) return;

                const modeling = modeler.get("modeling");
                const bpmnFactory = modeler.get("bpmnFactory");
                const canvas = modeler.get("canvas");
                const selection = modeler.get("selection");

                const root = canvas.getRootElement();
                const viewbox = canvas.viewbox();
                const size = DEFAULT_SIZES[type] || { w: 100, h: 80, name: "" };
                const position = {
                    x: viewbox.x + viewbox.width / 2,
                    y: viewbox.y + viewbox.height / 2
                };

                const bpmnType = TYPE_TO_BPMN[type];
                if (!bpmnType) return;

                const businessObject = bpmnFactory.create(bpmnType, {
                    id: uid(type),
                    name: size.name
                });

                const shape = modeling.createShape({ type: bpmnType, businessObject }, position, root);
                if (shape) {
                    selection.select(shape);
                }
            };

            const setMode = (m) => {
                mode.value = m;
                addType.value = null;

                const modeler = modelerRef.value;
                if (!modeler) return;

                const globalConnect = modeler.get("globalConnect");
                if (m === "connect" && globalConnect && typeof globalConnect.toggle === "function") {
                    globalConnect.toggle();
                }
            };

            const deleteSelected = () => {
                const modeler = modelerRef.value;
                if (!modeler) return;
                const selection = modeler.get("selection").get();
                if (!selection.length) return;
                modeler.get("modeling").removeElements(selection);
                selectedId.value = null;
                selectedIds.value = [];
                selectedElement.value = null;
            };

            onMounted(async () => {
                const modeler = new BpmnJS({
                    container: bpmnCanvasRef.value,
                    keyboard: { bindTo: window },
                    additionalModules: [createInfoContextPadModule()]
                });
                modelerRef.value = modeler;

                modeler.on("selection.changed", (event) => {
                    const selection = event.newSelection || [];
                    selectedIds.value = selection.map((element) => element.id);
                    selectedId.value = selection.length === 1 ? selection[0].id : null;
                    selectedElement.value = selection.length === 1 ? selection[0] : null;
                });

                modeler.on("element.changed", (event) => {
                    if (!selectedElement.value || selectedElement.value.id !== event.element.id) return;
                    selectedElement.value = event.element;
                });

                await modeler.importXML(EMPTY_BPMN_XML);
                modeler.get("canvas").zoom("fit-viewport", "auto");
                load();
                nextTick(resizeAiPrompt);
            });

            return {
                saving,
                mode,
                addType,
                modelName,
                sidebarMode,
                aiPrompt,
                aiPromptRef,
                aiGenerating,
                aiStepMessage,
                selectedIds,
                infoEditor,
                infoViewer,
                infoEditorRef,
                canEditSelectedInfo,
                setMode,
                beginAdd,
                sendAiPrompt,
                openInfoEditorFromSelection,
                openInfoViewerFromSelection,
                closeInfoEditor,
                closeInfoViewer,
                saveInfoEditor,
                onEditorInput,
                formatInfoEditor,
                save,
                deleteSelected,
                bpmnCanvasRef
            };
        }
    }).mount("#bpmnApp");
})();
