<%@ Page Language="C#" AutoEventWireup="true" %>
<!DOCTYPE html>
<html>
<head runat="server">
  <meta charset="utf-8" />
  <title>Frame BPMN</title>
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css" />
  <link rel="stylesheet" href="/Bpmn/frame-bpmn.css" />
</head>
<body>
  <form id="form1" runat="server">
    <div id="frameBpmnPage" class="frame-page">
      <header class="frame-header" id="frameHeader">
        <div>
          <h1 class="frame-title">Frame BPMN</h1>
        </div>
        <button type="button" class="maximize-button" id="maximizeButton" aria-pressed="false">
          <span id="maximizeLabel">Maximizar</span>
          <i class="fa-solid fa-expand" id="maximizeIcon" aria-hidden="true"></i>
        </button>
      </header>

      <main class="frame-content">
        <iframe
          class="bpmn-frame"
          title="Editor BPMN"
          src='BpmnEditor.aspx<%= Server.HtmlEncode(Request.Url.Query ?? string.Empty) %>'
        ></iframe>
      </main>
    </div>
  </form>

  <script>
    (function () {
      const page = document.getElementById('frameBpmnPage');
      const maximizeButton = document.getElementById('maximizeButton');
      const maximizeLabel = document.getElementById('maximizeLabel');
      const maximizeIcon = document.getElementById('maximizeIcon');
      let maximized = false;

      maximizeButton.addEventListener('click', function () {
        maximized = !maximized;
        page.classList.toggle('is-maximized', maximized);
        maximizeButton.setAttribute('aria-pressed', maximized ? 'true' : 'false');
        maximizeLabel.textContent = maximized ? 'Restaurar' : 'Maximizar';
        maximizeIcon.className = maximized ? 'fa-solid fa-compress' : 'fa-solid fa-expand';
      });
    })();
  </script>
</body>
</html>
