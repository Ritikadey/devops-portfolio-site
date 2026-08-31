// API base URL is injected at build time via GitHub Actions (see workflow),
// or set locally in a .env file. Falls back to empty = panel shows a fallback message.
const API_URL = import.meta.env.VITE_API_URL || '';
const BUILD_ID = import.meta.env.VITE_BUILD_ID || 'local';

/* ---------------------------------------------------------------------- */
/* Terminal boot sequence                                                  */
/* ---------------------------------------------------------------------- */
const BOOT_LINES = [
  '$ terraform apply -auto-approve',
  '  aws_s3_bucket.site: Creating...',
  '  aws_cloudfront_distribution.cdn: Creating...',
  '  aws_lambda_function.visitor_api: Creating...',
  '  aws_dynamodb_table.visitors: Creating...',
  'Apply complete! Resources: 12 added, 0 changed, 0 destroyed.',
  '',
  '$ gh workflow run deploy-frontend.yml',
  '  ✓ build        (vite build)',
  '  ✓ sync to s3',
  '  ✓ invalidate cloudfront',
  'Deployed in 41s.',
];

function typeTerminal() {
  const el = document.getElementById('terminalBody');
  if (!el) return;
  let line = 0;
  let char = 0;
  let out = '';

  function step() {
    if (line >= BOOT_LINES.length) return;
    const current = BOOT_LINES[line];
    if (char <= current.length) {
      el.textContent = out + current.slice(0, char);
      char += 1;
      setTimeout(step, current.length === 0 ? 60 : 14);
    } else {
      out += current + '\n';
      line += 1;
      char = 0;
      setTimeout(step, 90);
    }
  }
  step();
}

/* ---------------------------------------------------------------------- */
/* Live systems panel                                                      */
/* ---------------------------------------------------------------------- */
async function loadPanel() {
  const statusDot = document.getElementById('statusDot');
  const statusEl = document.getElementById('metricStatus');
  const latencyEl = document.getElementById('metricLatency');
  const visitorsEl = document.getElementById('metricVisitors');
  const fallback = document.getElementById('panelFallback');

  if (!API_URL) {
    statusEl.textContent = 'not configured';
    fallback.hidden = false;
    return;
  }

  try {
    const start = performance.now();
    const res = await fetch(`${API_URL}/visitors`, { method: 'POST' });
    const elapsed = Math.round(performance.now() - start);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();

    statusDot.classList.add('status-dot--ok');
    statusEl.textContent = 'operational';
    latencyEl.textContent = `${elapsed} ms`;
    visitorsEl.textContent = data.count ?? '—';
  } catch (err) {
    statusDot.classList.add('status-dot--down');
    statusEl.textContent = 'unreachable';
    latencyEl.textContent = '—';
    visitorsEl.textContent = '—';
    fallback.hidden = false;
    // eslint-disable-next-line no-console
    console.warn('Live panel: API not reachable yet.', err);
  }
}

/* ---------------------------------------------------------------------- */
/* Architecture diagram (inline SVG, theme-aware via CSS variables)        */
/* ---------------------------------------------------------------------- */
function renderDiagram() {
  const host = document.getElementById('architectureDiagram');
  if (!host) return;
  host.innerHTML = `
  <svg viewBox="0 0 900 300" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Architecture diagram: users connect through CloudFront to an S3 bucket for static assets, and through API Gateway to a Lambda function backed by DynamoDB for the visitor counter. GitHub Actions deploys to both paths using an OIDC role.">
    <defs>
      <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
        <path d="M0,0 L10,5 L0,10 z" fill="#8b92a0" />
      </marker>
    </defs>
    <style>
      text { font-family: 'JetBrains Mono', monospace; font-size: 12px; fill: #e8eaed; }
      .lbl { fill: #8b92a0; font-size: 10.5px; }
      .box { stroke-width: 1.4; fill: #171a21; }
      .edge { stroke: #ffb84d; }
      .compute { stroke: #3ddc97; }
      .ci { stroke: #7aa2ff; }
      line { stroke: #8b92a0; stroke-width: 1.2; }
    </style>

    <!-- Users -->
    <rect x="20" y="120" width="110" height="52" rx="8" class="box edge" />
    <text x="75" y="142" text-anchor="middle">Users</text>
    <text x="75" y="158" text-anchor="middle" class="lbl">browser</text>

    <!-- CloudFront -->
    <rect x="190" y="60" width="140" height="52" rx="8" class="box edge" />
    <text x="260" y="82" text-anchor="middle">CloudFront</text>
    <text x="260" y="98" text-anchor="middle" class="lbl">TLS · OAC · cache</text>

    <!-- S3 -->
    <rect x="400" y="60" width="140" height="52" rx="8" class="box edge" />
    <text x="470" y="82" text-anchor="middle">S3 bucket</text>
    <text x="470" y="98" text-anchor="middle" class="lbl">static assets (private)</text>

    <!-- API Gateway -->
    <rect x="190" y="180" width="140" height="52" rx="8" class="box compute" />
    <text x="260" y="202" text-anchor="middle">API Gateway</text>
    <text x="260" y="218" text-anchor="middle" class="lbl">HTTP API</text>

    <!-- Lambda -->
    <rect x="400" y="180" width="140" height="52" rx="8" class="box compute" />
    <text x="470" y="202" text-anchor="middle">Lambda</text>
    <text x="470" y="218" text-anchor="middle" class="lbl">container image</text>

    <!-- DynamoDB -->
    <rect x="610" y="180" width="140" height="52" rx="8" class="box compute" />
    <text x="680" y="202" text-anchor="middle">DynamoDB</text>
    <text x="680" y="218" text-anchor="middle" class="lbl">visitors table</text>

    <!-- GitHub Actions -->
    <rect x="610" y="60" width="220" height="52" rx="8" class="box ci" />
    <text x="720" y="82" text-anchor="middle">GitHub Actions</text>
    <text x="720" y="98" text-anchor="middle" class="lbl">OIDC role · build · deploy</text>

    <!-- Edges -->
    <line x1="130" y1="146" x2="188" y2="90" marker-end="url(#arrow)" />
    <line x1="130" y1="146" x2="188" y2="206" marker-end="url(#arrow)" />
    <line x1="330" y1="86" x2="398" y2="86" marker-end="url(#arrow)" />
    <line x1="330" y1="206" x2="398" y2="206" marker-end="url(#arrow)" />
    <line x1="540" y1="206" x2="608" y2="206" marker-end="url(#arrow)" />
    <line x1="720" y1="112" x2="470" y2="178" marker-end="url(#arrow)" stroke-dasharray="4 3" />
    <line x1="700" y1="112" x2="270" y2="178" marker-end="url(#arrow)" stroke-dasharray="4 3" />
  </svg>`;
}

/* ---------------------------------------------------------------------- */
/* Misc                                                                     */
/* ---------------------------------------------------------------------- */
function wirePingButton() {
  const btn = document.getElementById('pingBtn');
  if (!btn) return;
  btn.addEventListener('click', async () => {
    btn.textContent = 'Pinging…';
    await loadPanel();
    btn.textContent = 'Pinged ✓';
    setTimeout(() => { btn.textContent = 'Ping the API'; }, 1600);
  });
}

document.addEventListener('DOMContentLoaded', () => {
  typeTerminal();
  renderDiagram();
  loadPanel();
  wirePingButton();
  const buildEl = document.getElementById('footerBuild');
  if (buildEl) buildEl.textContent = BUILD_ID.slice(0, 7);
});
