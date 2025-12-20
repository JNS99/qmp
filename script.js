// =========================
//  Utilidades (compartidas)
// =========================
function escapeHtml(s) {
  return (s || '')
  .replaceAll('&', '&amp;')
  .replaceAll('<', '&lt;')
  .replaceAll('>', '&gt;');
}

function applyInlineFormatting(text) {
  return text
    // negrita: **texto**
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    // cursiva: *texto*
    .replace(/\*(.+?)\*/g, '<em>$1</em>');
}


function textToParagraphs(text) {
  const paragraphs = (text || '')
  .trim()
  .split(/\n\s*\n/)
  .map(p => p.trim())
  .filter(Boolean);

  return paragraphs
  .map((p, i) =>
    i === 0
    ? `<p class="analysis-lead">${applyInlineFormatting(escapeHtml(p))}</p>`
    : `<p>${applyInlineFormatting(escapeHtml(p))}</p>`
    )
  .join('');
}

// Parser que SOLO reconoce encabezados de sección exactos
function parseEntry(text) {
  const allowed = new Set(['POEMA', 'ANALISIS', 'POEMA_CITADO', 'TEXTO']);
  const sections = {};
  let current = null;

  (text || '').split('\n').forEach(line => {
    const m = line.match(/^#\s+(.+)\s*$/);
    if (m) {
      const name = m[1].trim();
      if (allowed.has(name)) {
        current = name;
        sections[current] = [];
      } else if (current) {
        // contenido dentro de una sección
        sections[current].push(line.replace(/^#\s+/, ''));
      }
      return;
    }
    if (current) sections[current].push(line);
  });

  return {
    poem: (sections['POEMA'] || []).join('\n').trim(),
    citedPoem: (sections['POEMA_CITADO'] || []).join('\n').trim(),
    analysisText: (sections['TEXTO'] || []).join('\n').trim()
  };
}

function renderPoemWithOptionalTitle(text) {
  const lines = (text || '').split('\n');

  // Si 1ª línea tiene texto y 2ª está vacía → asumimos título
  if (lines.length > 1 && lines[0].trim() && lines[1].trim() === '') {
    const title = lines[0].trim();
    const body = lines.slice(2).join('\n').trim();
    return `<div class="poem-title">${escapeHtml(title)}</div><pre>${escapeHtml(body)}</pre>`;
  }

  return `<pre>${escapeHtml((text || '').trim())}</pre>`;
}

function buildCitedMeta(entry) {
  const a = entry?.analysis || {};

  const title = a.poem_title || '';
  const sourceParts = [];

  if (a.poet) sourceParts.push(a.poet);
  if (a.book_title) sourceParts.push(a.book_title);

  return {
    title,
    source: sourceParts.join(' · ')
  };
}


function getTodayISO() {
  const d = new Date();
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}`;
}

function formatDate(dateStr) {
  const [y, m, d] = (dateStr || '').split('-');
  const months = ['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'];
  return `${parseInt(d, 10)} de ${months[parseInt(m, 10) - 1]} de ${y}`;
}

// =========================
//  UI: pestañas + URL ?a=1
// =========================
function getTabIds() {
  // index.html usa nav-*
  if (document.getElementById('nav-poem') && document.getElementById('nav-analysis')) {
    return { poemTab: 'nav-poem', analysisTab: 'nav-analysis' };
  }
  // passe.html usa past-*
  return { poemTab: 'past-poem', analysisTab: 'past-analysis' };
}

function showPoem() {
  const { poemTab, analysisTab } = getTabIds();

  document.getElementById('poemHeader')?.style && (document.getElementById('poemHeader').style.display = 'block');
  document.getElementById('poem')?.style && (document.getElementById('poem').style.display = 'block');
  document.getElementById('analysisHeader')?.style && (document.getElementById('analysisHeader').style.display = 'none');
  document.getElementById('analysis')?.style && (document.getElementById('analysis').style.display = 'none');

  document.getElementById(poemTab)?.classList.add('active');
  document.getElementById(analysisTab)?.classList.remove('active');
}

function showAnalysis() {
  const { poemTab, analysisTab } = getTabIds();

  document.getElementById('poemHeader')?.style && (document.getElementById('poemHeader').style.display = 'none');
  document.getElementById('poem')?.style && (document.getElementById('poem').style.display = 'none');
  document.getElementById('analysisHeader')?.style && (document.getElementById('analysisHeader').style.display = 'block');
  document.getElementById('analysis')?.style && (document.getElementById('analysis').style.display = 'block');

  document.getElementById(analysisTab)?.classList.add('active');
  document.getElementById(poemTab)?.classList.remove('active');
}

function applyViewFromURL() {
  const params = new URLSearchParams(window.location.search);
  if (params.get('a') === '1') showAnalysis();
  else showPoem();
}

function setURLForPoem() {
  const url = new URL(window.location.href);
  url.searchParams.delete('a'); // conserva ?date=...
  history.replaceState({}, '', url);
}

function setURLForAnalysis() {
  const url = new URL(window.location.href);
  url.searchParams.set('a', '1'); // conserva ?date=...
  history.replaceState({}, '', url);
}

// =========================
//  Carga de contenido
// =========================

function setCitedMeta(chosen) {
  const a = chosen?.analysis || {};

  const wrap = document.querySelector('.analysis-cited-meta');
  const titleEl = document.querySelector('.analysis-cited-title');
  const sourceEl = document.querySelector('.analysis-cited-source');

  // Si esa página no tiene este bloque, no hacemos nada
  if (!wrap || !titleEl || !sourceEl) return;

  const title = (a.poem_title || '').trim();
  const poet  = (a.poet || '').trim();
  const book  = (a.book_title || '').trim();

  // Si no hay nada, esconder
  if (!title && !poet && !book) {
    wrap.style.display = 'none';
    titleEl.textContent = '';
    sourceEl.textContent = '';
    return;
  }

  wrap.style.display = 'block';

  // Línea 1: título en negrita (sin comillas)
  titleEl.innerHTML = title ? `<strong>${escapeHtml(title)}</strong>` : '';
  titleEl.style.display = title ? 'block' : 'none';

  // Línea 2: autor / poemario
  const parts = [poet, book].filter(Boolean);
  sourceEl.textContent = parts.join(' · ');
  sourceEl.style.display = parts.length ? 'block' : 'none';
}

async function loadTodayEntry() {
  const index = await fetch('archivo.json').then(r => r.json());

  const today = getTodayISO();
  const byDateAsc = [...index].sort((a, b) => a.date.localeCompare(b.date));
  const chosen = index.find(e => e.date === today) || byDateAsc.at(-1);

  if (!chosen) {
    document.getElementById('poem').innerHTML = '<pre>No hay entradas todavía.</pre>';
    return;
  }

  const raw = await fetch(chosen.file).then(r => r.text());
  const parsed = parseEntry(raw);

  document.getElementById('poem').innerHTML = renderPoemWithOptionalTitle(parsed.poem);
  document.querySelector('.analysis-poem').textContent = parsed.citedPoem;
  document.querySelector('.analysis-text').innerHTML = textToParagraphs(parsed.analysisText);

  // Meta del poema citado (2 líneas)
  setCitedMeta(chosen);
}


async function loadPastEntry() {
  const params = new URLSearchParams(window.location.search);
  const date = params.get('date');

  if (!date) {
    document.getElementById('poem').innerHTML = '<pre>Falta el parámetro ?date=YYYY-MM-DD</pre>';
    return;
  }

  const pageDate = document.getElementById('pageDate');
  if (pageDate) pageDate.textContent = formatDate(date);

  const index = await fetch('archivo.json').then(r => r.json());
  const chosen = index.find(e => e.date === date);

  if (!chosen) {
    document.getElementById('poem').innerHTML = `<pre>No encontré la entrada para ${date}.</pre>`;
    return;
  }

  const raw = await fetch(chosen.file).then(r => r.text());
  const parsed = parseEntry(raw);

  document.getElementById('poem').innerHTML = renderPoemWithOptionalTitle(parsed.poem);
  document.querySelector('.analysis-poem').textContent = parsed.citedPoem;
  document.querySelector('.analysis-text').innerHTML = textToParagraphs(parsed.analysisText);

  setCitedMeta(chosen);
}


// =========================
//  Init (cuando el DOM existe)
// =========================
document.addEventListener('DOMContentLoaded', () => {
  // Clicks de pestañas (si existen)
  const poemTabEl = document.getElementById('nav-poem') || document.getElementById('past-poem');
  const analysisTabEl = document.getElementById('nav-analysis') || document.getElementById('past-analysis');

  if (poemTabEl) {
    poemTabEl.addEventListener('click', (e) => {
      e.preventDefault();
      setURLForPoem();
      showPoem();
    });
  }

  if (analysisTabEl) {
    analysisTabEl.addEventListener('click', (e) => {
      e.preventDefault();
      setURLForAnalysis();
      showAnalysis();
    });
  }

  window.addEventListener('popstate', applyViewFromURL);

  // Cargar contenido según la página
  const isPastPage = document.body.dataset.page === 'passe';

  const load = isPastPage ? loadPastEntry : loadTodayEntry;

  load().catch(err => {
    console.error(err);
    const poemEl = document.getElementById('poem');
    if (poemEl) poemEl.innerHTML = '<pre>Error cargando el texto.</pre>';
  });

  // Aplicar vista inicial según ?a=1
  applyViewFromURL();
});
