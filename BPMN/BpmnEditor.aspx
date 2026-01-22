<%@ Page Language="C#" AutoEventWireup="true"  CodeFile="BpmnEditor.aspx.cs" Inherits="BpmnEditor" %>
<!DOCTYPE html>
<html>
<head runat="server">
  <meta charset="utf-8" />
  <title>BPMN - Editor</title>
  <link rel="stylesheet" href="/Bpmn/bpmn-editor.css" />
</head>
<body>
<form id="form1" runat="server">
  <asp:ScriptManager ID="sm" runat="server" EnablePageMethods="true" />

  <script>
    // Id vem do QueryString
    window.__BPMN_MODEL_ID__ = <%= ModelId %>;
  </script>

  <div id="bpmnApp" class="page">
    <header class="topbar">
      <div class="left">
        <a class="link" href="/Bpmn/BpmnModels.aspx">← Voltar</a>
        <div class="titlewrap">
          <h1 class="title">Editor BPMN</h1>
          <p class="subtitle">Arraste, conecte e salve</p>
        </div>
      </div>

      <div class="actions">
        <button type="button" class="btn btn--ghost" @click="setMode('select')" :class="{ active: mode==='select' }">Selecionar</button>
        <button type="button" class="btn btn--ghost" @click="setMode('connect')" :class="{ active: mode==='connect' }">Conectar</button>

        <span class="divider"></span>

        <button type="button" class="btn btn--ghost" @click="save" :disabled="saving">{{ saving ? 'Salvando...' : 'Salvar' }}</button>
      </div>
    </header>

    <section class="layout">
      <aside class="sidebar card">
        <h3>Paleta</h3>
        <div class="palette">
          <button type="button" class="pill" @click="beginAdd('startEvent')">Start</button>
          <button type="button" class="pill" @click="beginAdd('task')">Task</button>
          <button type="button" class="pill" @click="beginAdd('exclusiveGateway')">Gateway</button>
          <button type="button" class="pill" @click="beginAdd('endEvent')">End</button>
        </div>

        <h3 style="margin-top:16px;">Modelo</h3>
        <label class="field">
          <span>Nome</span>
          <input class="input" v-model="modelName" />
        </label>

        <div class="toolbar">
          <button type="button" class="btn btn--danger" @click="deleteSelected" :disabled="!selectedId">Excluir selecionado</button>
        </div>

        <div class="hint">
          <div><strong>Modo adicionar:</strong> clique no canvas para inserir.</div>
          <div><strong>Conectar:</strong> clique no nó origem e depois no destino.</div>
          <div><strong>Mover:</strong> arraste o nó.</div>
        </div>
      </aside>

      <main class="canvas card">
        <svg
          ref="svgRef"
          class="svg"
          :viewBox="viewBox"
          @mousedown="onCanvasMouseDown"
        >
          <defs>
            <marker id="arrow" markerWidth="10" markerHeight="10" refX="9" refY="3" orient="auto" markerUnits="strokeWidth">
              <path d="M0,0 L10,3 L0,6 Z"></path>
            </marker>
          </defs>

          <!-- edges -->
          <g class="edges">
            <polyline
              v-for="e in edges"
              :key="e.id"
              :points="edgePoints(e)"
              class="edge"
              marker-end="url(#arrow)"
              @mousedown.stop="selectEdge(e.id)"
            />
          </g>

          <!-- nodes -->
          <g class="nodes">
            <template v-for="n in nodes" :key="n.id">
              <!-- task -->
              <g v-if="n.type==='task'" class="node" :class="{ selected: selectedId===n.id }"
                 :transform="`translate(${n.x},${n.y})`"
                 @mousedown.stop="onNodeDown($event, n)"
                 @click.stop="onNodeClick(n)">
                <rect :width="n.w" :height="n.h" rx="10" ry="10" />
                <text class="node-title" x="10" y="24">{{ n.name }}</text>
              </g>

              <!-- start/end -->
              <g v-else-if="n.type==='startEvent' || n.type==='endEvent'" class="node" :class="{ selected: selectedId===n.id }"
                 :transform="`translate(${n.x},${n.y})`"
                 @mousedown.stop="onNodeDown($event, n)"
                 @click.stop="onNodeClick(n)">
                <circle :cx="n.w/2" :cy="n.h/2" :r="n.w/2 - 2" :class="n.type" />
                <text class="node-title" :x="n.w/2" :y="n.h + 16" text-anchor="middle">{{ n.name }}</text>
              </g>

              <!-- gateway -->
              <g v-else-if="n.type==='exclusiveGateway'" class="node" :class="{ selected: selectedId===n.id }"
                 :transform="`translate(${n.x},${n.y})`"
                 @mousedown.stop="onNodeDown($event, n)"
                 @click.stop="onNodeClick(n)">
                <polygon :points="diamondPoints(n.w, n.h)" />
                <text class="node-title" :x="n.w/2" :y="n.h + 16" text-anchor="middle">{{ n.name }}</text>
              </g>
            </template>
          </g>

          <!-- connection preview -->
          <line v-if="connectPreview.show" class="edge preview"
                :x1="connectPreview.x1" :y1="connectPreview.y1"
                :x2="connectPreview.x2" :y2="connectPreview.y2"
                marker-end="url(#arrow)" />
        </svg>
      </main>
    </section>
  </div>

  <script src="https://unpkg.com/vue@3/dist/vue.global.prod.js"></script>
  <script src="/Bpmn/bpmn-editor.js"></script>
</form>
</body>
</html>
