(() => {
    // --- DEBUG: prova de carregamento do arquivo ---
    // Se você NÃO enxergar essa linha no console, ESTE arquivo não está sendo executado.
    // (Possíveis causas: cache, caminho incorreto, erro JS anterior impedindo execução, etc.)
    try {
        window.__BPMN_EDITOR_JS_LOADED__ = true;
        console.log('[bpmn-editor] script carregado', new Date().toISOString());
    } catch (e) { /* ignore */ }

    const { createApp, ref, reactive, computed, onMounted, onBeforeUnmount, nextTick, watch } = Vue;

    const uid = (prefix = "X") => `${prefix}_${Date.now()}_${Math.floor(Math.random() * 1e9)}`;

    const createToastManager = () => {
        let toastEl = null;
        let messageEl = null;
        let closeButton = null;
        let overlayEl = null;
        let hideTimer = null;
        let currentType = "success";

        const hideToast = () => {
            if (hideTimer) {
                clearTimeout(hideTimer);
                hideTimer = null;
            }
            if (toastEl) toastEl.classList.remove("is-active");
            if (overlayEl) overlayEl.classList.remove("is-active");
        };

        const ensureElements = () => {
            if (toastEl) return;

            overlayEl = document.createElement("div");
            overlayEl.className = "toast-overlay";

            toastEl = document.createElement("div");
            toastEl.className = "toast-container";

            messageEl = document.createElement("span");
            messageEl.className = "toast-message";

            closeButton = document.createElement("button");
            closeButton.type = "button";
            closeButton.className = "toast-close";
            closeButton.setAttribute("aria-label", "Fechar");
            closeButton.innerHTML = "&times;";
            closeButton.addEventListener("click", (event) => {
                event.stopPropagation();
                hideToast();
            });

            toastEl.addEventListener("click", () => {
                if (currentType !== "error") {
                    hideToast();
                }
            });

            toastEl.appendChild(messageEl);
            toastEl.appendChild(closeButton);
            document.body.appendChild(overlayEl);
            document.body.appendChild(toastEl);
        };

        const showToast = (message, type = "success") => {
            ensureElements();
            currentType = type;
            messageEl.textContent = message;
            toastEl.classList.remove("toast--success", "toast--error");
            toastEl.classList.add(`toast--${type}`);
            toastEl.classList.add("is-active");
            overlayEl.classList.add("is-active");

            if (hideTimer) {
                clearTimeout(hideTimer);
            }

            if (type !== "error") {
                hideTimer = setTimeout(hideToast, 2000);
            } else {
                hideTimer = null;
            }
        };

        return { showToast, hideToast };
    };

    const toast = createToastManager();

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

    const translations = {
        "Align elements": "Alinhar elementos",
        "Activate hand tool": "Ativar a ferramenta de mão",
        "Activate lasso tool": "Ativar a ferramenta de laço",
        "Activate create/remove space tool": "Ativar a ferramenta de criar/remover espaço",
        "Activate global connect tool": "Ativar a ferramenta de conexão global",
        "Create intermediate/boundary event": "Criar evento intermediário/de borda",
        "Create gateway": "Criar gateway",
        "Create expanded sub-process": "Criar subprocesso expandido",
        "Connect to other element": "Conectar a outro elemento",
        "Change element": "Alterar elemento",
        "Add text annotation": "Adicionar anotação",
        "Append {type}": "Adicionar {type}",
        "Append End Event": "Adicionar evento de fim",
        "Append Gateway": "Adicionar gateway",
        "Append Task": "Adicionar tarefa",
        "Connect": "Conectar",
        "Remove": "Remover",
        "Delete": "Excluir",
        "Cancel": "Cancelar",
        "Cancel Action": "Cancelar ação",
        "Undo": "Desfazer",
        "Redo": "Refazer",
        "Copy": "Copiar",
        "Paste": "Colar",
        "Create Shape": "Criar forma",
        "Create": "Criar",
        "Create Task": "Criar tarefa",
        "Create Start Event": "Criar evento de início",
        "Create End Event": "Criar evento de fim",
        "Create Intermediate Throw Event": "Criar evento intermediário (lançamento)",
        "Create Intermediate Catch Event": "Criar evento intermediário (captura)",
        "Create Boundary Event": "Criar evento de borda",
        "Create User Task": "Criar tarefa do usuário",
        "Create Service Task": "Criar tarefa de serviço",
        "Create Script Task": "Criar tarefa de script",
        "Create Business Rule Task": "Criar tarefa de regra de negócio",
        "Create Manual Task": "Criar tarefa manual",
        "Create Send Task": "Criar tarefa de envio",
        "Create Receive Task": "Criar tarefa de recebimento",
        "Create Call Activity": "Criar atividade de chamada",
        "Create Sub Process": "Criar subprocesso",
        "Create Expanded Sub Process": "Criar subprocesso expandido",
        "Create Collapsed Sub Process": "Criar subprocesso recolhido",
        "Create Transaction": "Criar transação",
        "Create Event Sub Process": "Criar subprocesso de evento",
        "Create Ad-hoc Sub Process": "Criar subprocesso ad hoc",
        "Create Exclusive Gateway": "Criar gateway exclusivo",
        "Create Inclusive Gateway": "Criar gateway inclusivo",
        "Create Parallel Gateway": "Criar gateway paralelo",
        "Create Event based Gateway": "Criar gateway baseado em evento",
        "Create Complex Gateway": "Criar gateway complexo",
        "Create Data Object Reference": "Criar objeto de dados",
        "Create Data Store Reference": "Criar repositório de dados",
        "Create Data Input": "Criar entrada de dados",
        "Create Data Output": "Criar saída de dados",
        "Create Text Annotation": "Criar anotação de texto",
        "Create Group": "Criar grupo",
        "Create Participant": "Criar participante",
        "Create Pool/Participant": "Criar pool/participante",
        "Create Lane": "Criar raia",
        "Create Collaboration": "Criar colaboração",
        "Create Data Object": "Criar objeto de dados",
        "Start Event": "Evento de início",
        "End Event": "Evento de fim",
        "Intermediate Throw Event": "Evento intermediário (lançamento)",
        "Intermediate Catch Event": "Evento intermediário (captura)",
        "Boundary Event": "Evento de borda",
        "Task": "Tarefa",
        "User Task": "Tarefa do usuário",
        "Service Task": "Tarefa de serviço",
        "Script Task": "Tarefa de script",
        "Business Rule Task": "Tarefa de regra de negócio",
        "Manual Task": "Tarefa manual",
        "Send Task": "Tarefa de envio",
        "Receive Task": "Tarefa de recebimento",
        "Call Activity": "Atividade de chamada",
        "Sub Process": "Subprocesso",
        "Expanded Sub Process": "Subprocesso expandido",
        "Collapsed Sub Process": "Subprocesso recolhido",
        "Transaction": "Transação",
        "Event Sub Process": "Subprocesso de evento",
        "Ad-hoc Sub Process": "Subprocesso ad hoc",
        "Exclusive Gateway": "Gateway exclusivo",
        "Inclusive Gateway": "Gateway inclusivo",
        "Parallel Gateway": "Gateway paralelo",
        "Event based Gateway": "Gateway baseado em evento",
        "Complex Gateway": "Gateway complexo",
        "Data Object Reference": "Objeto de dados",
        "Data Store Reference": "Repositório de dados",
        "Data Input": "Entrada de dados",
        "Data Output": "Saída de dados",
        "Text Annotation": "Anotação de texto",
        "Group": "Grupo",
        "Participant": "Participante",
        "Lane": "Raia",
        "Start Event (None)": "Evento de início (nenhum)",
        "Intermediate Throw Event (None)": "Evento intermediário (nenhum)",
        "Intermediate Catch Event (None)": "Evento intermediário (nenhum)",
        "End Event (None)": "Evento de fim (nenhum)",
        "Activate the hand tool": "Ativar a ferramenta de mão",
        "Activate the lasso tool": "Ativar a ferramenta de laço",
        "Activate the global connect tool": "Ativar a ferramenta de conexão global",
        "Activate the space tool": "Ativar a ferramenta de espaço",
        "Activate the selection tool": "Ativar a ferramenta de seleção",
        "Activate the create/remove space tool": "Ativar a ferramenta de criar/remover espaço",
        "Create/Remove Space": "Criar/remover espaço",
        "Hand Tool": "Ferramenta de mão",
        "Lasso Tool": "Ferramenta de laço",
        "Space Tool": "Ferramenta de espaço",
        "Global Connect Tool": "Ferramenta de conexão global",
        "Activate the hand tool (H)": "Ativar a ferramenta de mão (H)",
        "Activate the lasso tool (L)": "Ativar a ferramenta de laço (L)",
        "Activate the global connect tool (C)": "Ativar a ferramenta de conexão global (C)",
        "Activate the create/remove space tool (S)": "Ativar a ferramenta de criar/remover espaço (S)",
        "Activate the space tool (S)": "Ativar a ferramenta de espaço (S)",
        "Activate the selection tool (S)": "Ativar a ferramenta de seleção (S)",
        "Press space to toggle selection": "Pressione espaço para alternar seleção",
        "Press space to toggle hand tool": "Pressione espaço para alternar ferramenta de mão",
        "Press space to toggle lasso tool": "Pressione espaço para alternar ferramenta de laço",
        "Press space to toggle create/remove space tool": "Pressione espaço para alternar criar/remover espaço",
        "Zoom In": "Aumentar zoom",
        "Zoom Out": "Diminuir zoom",
        "Zoom": "Zoom",
        "Fit viewport": "Ajustar à tela",
        "Reset zoom": "Redefinir zoom",
        "Event": "Evento",
        "Gateway": "Gateway",
        "General": "Geral",
        "Activities": "Atividades",
        "Events": "Eventos",
        "Gateways": "Gateways",
        "Data Objects": "Objetos de dados"
    };

    const typeTranslations = {
        Event: "Evento",
        Task: "Tarefa",
        Gateway: "Gateway",
        "Start Event": "Evento de início",
        "End Event": "Evento de fim",
        "Intermediate Throw Event": "Evento intermediário (lançamento)",
        "Intermediate Catch Event": "Evento intermediário (captura)",
        "Boundary Event": "Evento de borda",
        "User Task": "Tarefa do usuário",
        "Service Task": "Tarefa de serviço",
        "Script Task": "Tarefa de script",
        "Business Rule Task": "Tarefa de regra de negócio",
        "Manual Task": "Tarefa manual",
        "Send Task": "Tarefa de envio",
        "Receive Task": "Tarefa de recebimento",
        "Call Activity": "Atividade de chamada",
        "Sub Process": "Subprocesso",
        "Transaction": "Transação",
        "Event Sub Process": "Subprocesso de evento",
        "Ad-hoc Sub Process": "Subprocesso ad hoc",
        "Exclusive Gateway": "Gateway exclusivo",
        "Inclusive Gateway": "Gateway inclusivo",
        "Parallel Gateway": "Gateway paralelo",
        "Event based Gateway": "Gateway baseado em evento",
        "Complex Gateway": "Gateway complexo"
    };

    const customTranslate = (template, replacements) => {
        replacements = replacements || {};

        const raw = String(template || "");

        // tenta match exato
        let translated = translations[raw];

        // tenta variações comuns (bpmn-js 16+ mudou casing de várias labels)
        if (!translated) {
            const compact = raw.replace(/\s+/g, " ").trim();
            translated = translations[compact] || translated;

            if (!translated) {
                const titleCase = compact.replace(/\b[a-z]/g, (m) => m.toUpperCase());
                translated = translations[titleCase] || translated;
            }

            if (!translated) {
                const lower = compact.toLowerCase();
                translated = translations[lower] || translated;
            }
        }

        // se não tiver no dicionário, devolve a original e loga (pra você completar o mapa)
        if (!translated) {
            const params = new URLSearchParams(window.location.search || "");
            if (params.has("debugTranslate")) {
                console.warn("[bpmn-i18n] missing:", raw);
            }
            translated = raw;
        }

        // replace {tokens}
        return translated.replace(/{([^}]+)}/g, (_, key) => {
            return (replacements[key] !== undefined) ? replacements[key] : `{${key}}`;
        });
    };


    const customTranslateModule = {
        translate: ["value", customTranslate]
    };

    // ============================================================
    //  FORCE-TRANSLATE tooltips already rendered as DOM attributes
    //  (some bpmn-js parts write english titles directly; translate()
    //   won't retroactively change them)
    // ============================================================
    const installUiTooltipTranslator = (modeler) => {
        if (!modeler || typeof modeler.get !== "function") return () => { };
        const translate = modeler.get("translate");
        if (typeof translate !== "function") return () => { };

        const ATTRS = ["title", "aria-label", "data-title", "data-tooltip"];
        const SELECTOR =
            ".djs-palette, .djs-context-pad, .djs-popup, .bjs-powered-by, .djs-overlay-container";

        const translateOneAttr = (el, attr) => {
            if (!el || !el.getAttribute) return;
            const raw = el.getAttribute(attr);
            if (!raw) return;

            const translated = translate(raw);

            if (translated && translated !== raw) {
                el.setAttribute(attr, translated);
            }
            else {
                // If debugTranslate=1, log keys that are still missing
                try {
                    const params = new URLSearchParams(window.location.search || "");
                    if (params.has("debugTranslate")) {
                        window.__BPMN_I18N_MISSING__ = window.__BPMN_I18N_MISSING__ || {};
                        if (!window.__BPMN_I18N_MISSING__[raw]) {
                            window.__BPMN_I18N_MISSING__[raw] = true;
                            console.debug("[bpmn-i18n] missing:", raw);
                        }
                    }
                } catch { /* ignore */ }
            }
        };

        const patchDomTooltips = () => {
            const rootNodes = document.querySelectorAll(SELECTOR);
            rootNodes.forEach((root) => {
                ATTRS.forEach((a) => translateOneAttr(root, a));

                const nodes = root.querySelectorAll(
                    ATTRS.map(a => `[${a}]`).join(",")
                );
                nodes.forEach((el) => {
                    ATTRS.forEach((a) => translateOneAttr(el, a));
                });
            });
        };

        // Patch now + after next paint (some tooltips appear after render)
        try { patchDomTooltips(); } catch { }
        requestAnimationFrame(() => { try { patchDomTooltips(); } catch { } });

        // Keep patching on UI changes
        const obs = new MutationObserver(() => {
            try { patchDomTooltips(); } catch { }
        });

        obs.observe(document.body, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ATTRS
        });

        return () => {
            try { obs.disconnect(); } catch { }
        };
    };

    createApp({
        setup() {
            const modelId = window.__BPMN_MODEL_ID__ || 0;
            const params = new URLSearchParams(window.location.search || "");
            const modeParam = (params.get("mode") || "").toLowerCase();
            const isReadOnly = ref(modeParam === "view" || modeParam === "readonly");
            const aiEnabled = ref(Boolean(window.__BPMN_AI_ENABLED__) && !isReadOnly.value);

            const saving = ref(false);
            const mode = ref("select");
            const addType = ref(null);

            const modelName = ref("");
            const processDescription = ref("");
            const sidebarMode = ref("edit");
            const aiPrompt = ref("");
            const aiPromptRef = ref(null);
            const processDescriptionRef = ref(null);

            const modelerRef = ref(null);
            const bpmnCanvasRef = ref(null);
            const showShortcuts = ref(false);
            const shortcutsRef = ref(null);
            const shortcutsButtonRef = ref(null);

            const selectedId = ref(null);
            const selectedIds = ref([]);
            const selectedElement = ref(null);

            const infoEditorRef = ref(null);
            const infoPanelName = ref("");
            const infoEditorDirty = ref(false);
            const infoEditorOriginal = ref("");

            const aiGenerating = ref(false);
            const aiSteps = [
                "Pensando...",
                "Carregando informações...",
                "Processando os dados...",
                "Gerando o gráfico..."
            ];
            const aiStepIndex = ref(0);
            const aiStepMessage = computed(() => aiSteps[aiStepIndex.value]);
            const subtitleText = computed(() => (isReadOnly.value ? "Somente leitura" : "Arraste, conecte e salve"));
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
                return Boolean(element && !element.isRoot && !isReadOnly.value);
            });

            const getElementName = (element) => element?.businessObject?.name || "";

            const openInfoEditor = (element) => {
                if (isReadOnly.value) return;
                if (!element) return;
                if (infoEditor.show && infoEditorDirty.value && !confirmDiscardInfo()) {
                    return;
                }
                selectedId.value = element.id;
                infoViewer.show = false;
                infoEditor.elementId = element.id;
                infoEditor.content = element.businessObject?.$attrs?.infoHtml ?? "";
                infoEditorOriginal.value = infoEditor.content;
                infoEditorDirty.value = false;
                infoPanelName.value = getElementName(element);
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
                infoPanelName.value = "";
                infoEditorDirty.value = false;
                infoEditorOriginal.value = "";
            };

            const onEditorInput = () => {
                if (isReadOnly.value) return;
                infoEditor.content = infoEditorRef.value ? infoEditorRef.value.innerHTML : "";
                infoEditorDirty.value = infoEditor.content !== infoEditorOriginal.value;
            };

            const formatInfoEditor = (command, value = null) => {
                if (isReadOnly.value) return;
                if (!infoEditorRef.value) return;
                infoEditorRef.value.focus();
                if (command === "createLink") {
                    const url = window.prompt("Informe o link:");
                    if (url) {
                        document.execCommand(command, false, url);
                    }
                    return;
                }
                document.execCommand(command, false, value);
            };

            const toggleShortcuts = () => {
                showShortcuts.value = !showShortcuts.value;
            };

            const closeShortcuts = () => {
                showShortcuts.value = false;
            };

            const handleDocumentClick = (event) => {
                if (!showShortcuts.value) return;
                const target = event.target;
                if (shortcutsRef.value && shortcutsRef.value.contains(target)) return;
                if (shortcutsButtonRef.value && shortcutsButtonRef.value.contains(target)) return;
                closeShortcuts();
            };

            const saveInfoEditor = () => {
                if (isReadOnly.value) return;
                const modeler = modelerRef.value;
                if (!modeler || !infoEditor.elementId) return;
                const elementRegistry = modeler.get("elementRegistry");
                const element = elementRegistry.get(infoEditor.elementId);
                if (!element) return;
                const html = infoEditorRef.value ? infoEditorRef.value.innerHTML : infoEditor.content;
                const attrs = ensureAttrs(element.businessObject);
                attrs.infoHtml = html;
                infoEditorDirty.value = false;
                infoEditorOriginal.value = html;
                closeInfoEditor();
            };

            const getProcessDefinition = (modeler) => {
                if (!modeler) return null;
                const definitions = modeler.getDefinitions ? modeler.getDefinitions() : null;
                if (!definitions || !definitions.rootElements) return null;
                return definitions.rootElements.find((element) => element.$type === "bpmn:Process") || null;
            };

            const setProcessDescriptionFromModeler = () => {
                const modeler = modelerRef.value;
                const process = getProcessDefinition(modeler);
                const html = process?.$attrs?.processDescriptionHtml ?? "";
                processDescription.value = html;
                nextTick(() => {
                    if (processDescriptionRef.value) {
                        processDescriptionRef.value.innerHTML = html;
                    }
                });
            };

            const syncProcessDescriptionToModeler = () => {
                const modeler = modelerRef.value;
                const process = getProcessDefinition(modeler);
                if (!process) return;
                const html = processDescriptionRef.value ? processDescriptionRef.value.innerHTML : processDescription.value;
                const attrs = ensureAttrs(process);
                attrs.processDescriptionHtml = html;
                processDescription.value = html;
            };

            const onProcessDescriptionInput = () => {
                if (isReadOnly.value) return;
                syncProcessDescriptionToModeler();
            };

            const formatProcessDescription = (command, value = null) => {
                if (isReadOnly.value) return;
                if (!processDescriptionRef.value) return;
                processDescriptionRef.value.focus();
                if (command === "createLink") {
                    const url = window.prompt("Informe o link:");
                    if (url) {
                        document.execCommand(command, false, url);
                        syncProcessDescriptionToModeler();
                    }
                    return;
                }
                document.execCommand(command, false, value);
                syncProcessDescriptionToModeler();
            };

            const openInfoViewer = (element) => {
                if (!element) return;
                if (infoEditor.show && infoEditorDirty.value && !confirmDiscardInfo()) {
                    return;
                }
                selectedId.value = element.id;
                infoEditor.show = false;
                infoViewer.elementId = element.id;
                infoViewer.content = element.businessObject?.$attrs?.infoHtml ?? "";
                infoPanelName.value = getElementName(element);
                infoViewer.show = true;
            };

            const openInfoViewerFromSelection = () => {
                if (!canEditSelectedInfo.value) return;
                openInfoViewer(selectedElement.value);
            };

            const closeInfoViewer = () => {
                infoViewer.show = false;
                infoViewer.elementId = null;
                infoViewer.content = "";
                infoPanelName.value = "";
            };

            const confirmDiscardInfo = () => window.confirm("Existem informações não salvas. Deseja sair sem salvar?");

            const requestCloseInfoEditor = () => {
                if (infoEditorDirty.value && !confirmDiscardInfo()) {
                    return;
                }
                closeInfoEditor();
            };

            const handleBack = () => {
                if (infoEditor.show && infoEditorDirty.value && !confirmDiscardInfo()) {
                    return;
                }
                window.location.href = "/Bpmn/BpmnModels.aspx";
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
                                setProcessDescriptionFromModeler();
                            })
                            .catch((err) => {
                                console.error(err);
                                toast.showToast("XML inválido no banco. Carregando vazio.", "error");
                                modelerRef.value.importXML(EMPTY_BPMN_XML).then(() => {
                                    modelerRef.value.get("canvas").zoom("fit-viewport", "auto");
                                    setProcessDescriptionFromModeler();
                                });
                            });
                    },
                    (err) => {
                        console.error(err);
                        toast.showToast("Erro ao carregar modelo.", "error");
                    }
                );
            };

            const save = async () => {
                if (isReadOnly.value) {
                    toast.showToast("Modo somente leitura. Clique em editar para salvar alterações.", "error");
                    return;
                }
                saving.value = true;
                syncProcessDescriptionToModeler();
                const xml = await getCurrentXml();

                PageMethods.SaveModel(
                    modelId,
                    modelName.value || "Processo",
                    xml,
                    () => { saving.value = false; toast.showToast("Salvo com sucesso.", "success"); },
                    (err) => { console.error(err); saving.value = false; toast.showToast("Erro ao salvar.", "error"); }
                );
            };

            const sendAiPrompt = async () => {
                if (isReadOnly.value) return;
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
                            toast.showToast("A IA retornou um XML vazio.", "error");
                            return;
                        }

                        modelerRef.value.importXML(xml)
                            .then(() => {
                                modelerRef.value.get("canvas").zoom("fit-viewport", "auto");
                                setProcessDescriptionFromModeler();
                            })
                            .catch((e) => {
                                console.error("AI returned invalid XML:", res);
                                toast.showToast("A IA retornou um XML inválido. Veja o console.", "error");
                                console.error(e);
                            });

                        aiPrompt.value = "";
                        nextTick(resizeAiPrompt);
                        sidebarMode.value = "edit";
                    },
                    (err) => {
                        aiGenerating.value = false;
                        console.error(err);
                        toast.showToast((err && err.get_message) ? err.get_message() : "Erro ao chamar IA.", "error");
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
                if (isReadOnly.value) return;
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
                if (isReadOnly.value) return;
                mode.value = m;
                addType.value = null;

                const modeler = modelerRef.value;
                if (!modeler) return;

                const globalConnect = modeler.get("globalConnect");
                if (m === "connect" && globalConnect && typeof globalConnect.toggle === "function") {
                    globalConnect.toggle();
                }
            };

            const zoomIn = () => {
                const modeler = modelerRef.value;
                if (!modeler) return;
                const canvas = modeler.get("canvas");
                const currentZoom = canvas.zoom();
                const nextZoom = Math.min(currentZoom + 0.2, 2.5);
                canvas.zoom(nextZoom);
            };

            const zoomOut = () => {
                const modeler = modelerRef.value;
                if (!modeler) return;
                const canvas = modeler.get("canvas");
                const currentZoom = canvas.zoom();
                const nextZoom = Math.max(currentZoom - 0.2, 0.2);
                canvas.zoom(nextZoom);
            };

            const recenterCanvas = () => {
                const modeler = modelerRef.value;
                if (!modeler) return;
                modeler.get("canvas").zoom("fit-viewport", "auto");
            };

            const deleteSelected = () => {
                if (isReadOnly.value) return;
                const modeler = modelerRef.value;
                if (!modeler) return;
                const selection = modeler.get("selection").get();
                if (!selection.length) return;
                modeler.get("modeling").removeElements(selection);
                selectedId.value = null;
                selectedIds.value = [];
                selectedElement.value = null;
            };

            const parseSvgSize = (svgText) => {
                const doc = new DOMParser().parseFromString(svgText, "image/svg+xml");
                const svg = doc.documentElement;
                const widthAttr = svg.getAttribute("width");
                const heightAttr = svg.getAttribute("height");
                const viewBox = svg.getAttribute("viewBox");

                const parseNumber = (value) => {
                    if (!value) return null;
                    const parsed = parseFloat(value.toString().replace("px", "").trim());
                    return Number.isFinite(parsed) ? parsed : null;
                };

                const width = parseNumber(widthAttr);
                const height = parseNumber(heightAttr);
                if (width && height) {
                    return { width, height };
                }

                if (viewBox) {
                    const parts = viewBox.split(/\s+/).map((part) => parseFloat(part));
                    if (parts.length === 4 && parts.every((value) => Number.isFinite(value))) {
                        return { width: parts[2], height: parts[3] };
                    }
                }

                return { width: 1200, height: 800 };
            };

            const downloadBlob = (blob, filename) => {
                const url = URL.createObjectURL(blob);
                const link = document.createElement("a");
                link.href = url;
                link.download = filename;
                document.body.appendChild(link);
                link.click();
                link.remove();
                URL.revokeObjectURL(url);
            };

            const exportAsImage = async () => {
                const modeler = modelerRef.value;
                if (!modeler) return;
                try {
                    const { svg } = await modeler.saveSVG();
                    if (!svg) {
                        toast.showToast("Não foi possível gerar a imagem.", "error");
                        return;
                    }

                    const { width, height } = parseSvgSize(svg);
                    const scale = 2;
                    const canvas = document.createElement("canvas");
                    canvas.width = Math.ceil(width * scale);
                    canvas.height = Math.ceil(height * scale);
                    const ctx = canvas.getContext("2d");
                    if (!ctx) {
                        toast.showToast("Seu navegador não suporta exportação de imagem.", "error");
                        return;
                    }

                    ctx.fillStyle = "#ffffff";
                    ctx.fillRect(0, 0, canvas.width, canvas.height);
                    ctx.scale(scale, scale);

                    const svgBlob = new Blob([svg], { type: "image/svg+xml;charset=utf-8" });
                    const url = URL.createObjectURL(svgBlob);
                    const img = new Image();
                    img.onload = () => {
                        ctx.drawImage(img, 0, 0);
                        canvas.toBlob((blob) => {
                            if (!blob) {
                                toast.showToast("Falha ao gerar a imagem.", "error");
                                URL.revokeObjectURL(url);
                                return;
                            }
                            downloadBlob(blob, "bpmn-diagrama.png");
                            URL.revokeObjectURL(url);
                        }, "image/png");
                    };
                    img.onerror = () => {
                        toast.showToast("Falha ao carregar o diagrama.", "error");
                        URL.revokeObjectURL(url);
                    };
                    img.src = url;
                } catch (err) {
                    console.error(err);
                    toast.showToast("Erro ao exportar imagem.", "error");
                }
            };

            const exportAsPdf = async () => {
                const modeler = modelerRef.value;
                if (!modeler) return;
                try {
                    const { svg } = await modeler.saveSVG();
                    if (!svg) {
                        toast.showToast("Não foi possível gerar o PDF.", "error");
                        return;
                    }

                    const printWindow = window.open("", "_blank");
                    if (!printWindow) {
                        toast.showToast("Permita pop-ups para exportar em PDF.", "error");
                        return;
                    }

                    printWindow.document.write(`
                      <!doctype html>
                      <html>
                        <head>
                          <title>Exportar PDF</title>
                          <style>
                            html, body {
                              margin: 0;
                              padding: 0;
                              width: 100%;
                              height: 100%;
                              background: #fff;
                            }
                            .print-container {
                              display: flex;
                              align-items: center;
                              justify-content: center;
                              width: 100%;
                              height: 100%;
                              padding: 24px;
                              box-sizing: border-box;
                            }
                            svg {
                              width: 100%;
                              height: auto;
                            }
                          </style>
                        </head>
                        <body>
                          <div class="print-container">${svg}</div>
                        </body>
                      </html>
                    `);
                    printWindow.document.close();
                    printWindow.focus();
                    setTimeout(() => {
                        printWindow.print();
                        printWindow.close();
                    }, 300);
                } catch (err) {
                    console.error(err);
                    toast.showToast("Erro ao exportar PDF.", "error");
                }
            };

            const registerInfoContextPad = (modeler) => {
                if (!modeler) return;
                const contextPad = modeler.get("contextPad");
                if (!contextPad) return;

                const provider = {
                    getContextPadEntries(element) {
                        if (!element || element.isRoot) {
                            return {};
                        }

                        if (isReadOnly.value) {
                            return {
                                "info.view": {
                                    group: "info",
                                    className: "context-pad-icon context-pad-icon--view",
                                    title: "Visualizar informações",
                                    action: {
                                        click: (event, target) => openInfoViewer(target || element)
                                    }
                                }
                            };
                        }

                        return {
                            "info.edit": {
                                group: "info",
                                className: "context-pad-icon context-pad-icon--edit",
                                title: "Editar informações",
                                action: {
                                    click: (event, target) => openInfoEditor(target || element)
                                }
                            },
                            "info.view": {
                                group: "info",
                                className: "context-pad-icon context-pad-icon--view",
                                title: "Visualizar informações",
                                action: {
                                    click: (event, target) => openInfoViewer(target || element)
                                }
                            }
                        };
                    }
                };

                contextPad.registerProvider(provider);
            };

            const applyReadOnlyGuards = (modeler) => {
                if (!modeler || !isReadOnly.value) return;
                const commandStack = modeler.get("commandStack");
                if (commandStack && !commandStack.__readonlyWrapped) {
                    const originalExecute = commandStack.execute.bind(commandStack);
                    commandStack.execute = (command, ctx) => {
                        if (isReadOnly.value) {
                            return;
                        }
                        return originalExecute(command, ctx);
                    };
                    commandStack.__readonlyWrapped = true;
                }

                const palette = modeler.get("palette");
                if (palette && palette._container) {
                    palette._container.style.display = "none";
                }

                const contextPad = modeler.get("contextPad");
                if (contextPad && !contextPad.__readonlyWrapped) {
                    const originalGetEntries = contextPad.getEntries.bind(contextPad);
                    contextPad.getEntries = (element) => {
                        if (!isReadOnly.value) {
                            return originalGetEntries(element);
                        }
                        const entries = originalGetEntries(element) || {};
                        if (entries["info.view"]) {
                            return { "info.view": entries["info.view"] };
                        }
                        return {};
                    };
                    contextPad.__readonlyWrapped = true;
                }
            };

            onMounted(async () => {
                document.addEventListener("click", handleDocumentClick);
                if (!aiEnabled.value) {
                    sidebarMode.value = "edit";
                }
                const createAppendAnythingModule =
                    window.BpmnJSCreateAppendAnything ||
                    window.bpmnJSCreateAppendAnything ||
                    window.createAppendAnything ||
                    window.createAppendAnythingModule ||
                    null;
                if (!createAppendAnythingModule) {
                    console.warn("[bpmn-editor] bpmn-js-create-append-anything não carregado; a opção de criação pode ficar indisponível.");
                }

                const modeler = new BpmnJS({
                    container: bpmnCanvasRef.value,
                    keyboard: { bindTo: window },
                    additionalModules: [
                        customTranslateModule,
                        ...(createAppendAnythingModule ? [createAppendAnythingModule] : [])
                    ]
                });
                modelerRef.value = modeler;



                // Force-translate tooltips already painted in the DOM
                const __disposeTooltipI18n = installUiTooltipTranslator(modeler);
                // Diagnóstico / status de i18n
                try {
                    const params = new URLSearchParams(window.location.search || "");
                    const translate = modeler.get("translate");
                    const testKey = "Activate the global connect tool";
                    const testValue = translate(testKey);
                    const ok = (translate("Connect") === "Conectar") || (testValue !== testKey);

                    window.__BPMN_I18N__ = { ok, testKey, testValue };

                    const el = document.getElementById("bpmnI18nStatus");
                    if (el) {
                        el.style.display = params.has("debugTranslate") ? "block" : "none";
                        el.textContent = ok
                            ? "i18n OK: " + testValue
                            : "i18n NÃO aplicado (ainda em inglês): " + testValue;
                    }

                    if (params.has("debugTranslate")) {
                        console.log("[bpmn-i18n] test:", { testKey, testValue, ok });
                    }
                } catch (e) {
                    try { console.warn("[bpmn-i18n] falha no diagnóstico", e); } catch { }
                }

                registerInfoContextPad(modeler);
                applyReadOnlyGuards(modeler);

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
                setProcessDescriptionFromModeler();
                load();
                nextTick(resizeAiPrompt);
            });

            onBeforeUnmount(() => {
                document.removeEventListener("click", handleDocumentClick);
            });

            return {
                saving,
                aiEnabled,
                isReadOnly,
                mode,
                addType,
                modelName,
                processDescription,
                sidebarMode,
                aiPrompt,
                aiPromptRef,
                processDescriptionRef,
                showShortcuts,
                shortcutsRef,
                shortcutsButtonRef,
                aiGenerating,
                aiStepMessage,
                subtitleText,
                selectedIds,
                infoEditor,
                infoViewer,
                infoPanelName,
                infoEditorRef,
                canEditSelectedInfo,
                setMode,
                beginAdd,
                sendAiPrompt,
                onProcessDescriptionInput,
                formatProcessDescription,
                openInfoEditorFromSelection,
                openInfoViewerFromSelection,
                closeInfoEditor,
                requestCloseInfoEditor,
                closeInfoViewer,
                saveInfoEditor,
                onEditorInput,
                formatInfoEditor,
                toggleShortcuts,
                save,
                handleBack,
                deleteSelected,
                zoomIn,
                zoomOut,
                recenterCanvas,
                exportAsImage,
                exportAsPdf,
                bpmnCanvasRef
            };
        }
    }).mount("#bpmnApp");
})();
