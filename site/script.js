// =========================
//  Utilidades (compartidas)
// =========================

function txtPathFromDate(dateStr) {
  const y = dateStr.slice(0, 4);
  const m = dateStr.slice(5, 7);
  return `/textos/${y}/${m}/${dateStr}.txt`;
}

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
    poem: (sections['POEMA'] || []).join('\n').replace(/\s+$/,''),
    citedPoem: (sections['POEMA_CITADO'] || []).join('\n').trim(),
    analysisText: (sections['TEXTO'] || []).join('\n').trim()
  };
}

function renderPoemWithOptionalTitle(text) {
  if (!text) return '';

  const lines = text.split('\n');

  // Busca la primera línea no vacía
  let i = 0;
  while (i < lines.length && lines[i].trim() === '') i++;

  // Si hay una línea de texto y la siguiente línea es vacía => título
  if (i < lines.length - 1 && lines[i].trim() && lines[i + 1].trim() === '') {
    const title = lines[i].trim();
    const body = lines.slice(i + 2).join('\n').replace(/\s+$/,''); // conserva formato del poema

    return `<div class="poem-title">${escapeHtml(title)}</div><pre>${escapeHtml(body)}</pre>`;
  }

  // Sin título
  return `<pre>${escapeHtml(text.replace(/\s+$/,''))}</pre>`;
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

  // Si la página no tiene ese bloque, no hacemos nada
  if (!wrap || !titleEl || !sourceEl) return;

  const title = (a.poem_title || '').trim();
  const poet  = (a.poet || '').trim();
  const book  = (a.book_title || '').trim();

  // Si no hay nada, ocultamos el bloque
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

  // Línea 2: autor · poemario (solo lo que exista)
  const parts = [poet, book].filter(Boolean);
  sourceEl.textContent = parts.join(' · ');
  sourceEl.style.display = parts.length ? 'block' : 'none';
}

function measureTextPx(text, referenceEl) {
  const canvas = document.createElement('canvas');
  const ctx = canvas.getContext('2d');

  const cs = window.getComputedStyle(referenceEl);
  // font shorthand suficiente para measureText
  ctx.font = `${cs.fontStyle} ${cs.fontVariant} ${cs.fontWeight} ${cs.fontSize} ${cs.fontFamily}`;

  return ctx.measureText(text).width;
}

function renderPoemWithAnchorIndents(poemText, preEl) {
  const lines = (poemText || '').split('\n');

  // Medir con la misma fuente que el <pre>
  const canvas = document.createElement('canvas');
  const ctx = canvas.getContext('2d');
  const cs = window.getComputedStyle(preEl);

  ctx.font = `${cs.fontStyle} ${cs.fontVariant} ${cs.fontWeight} ${cs.fontSize} ${cs.fontFamily}`;

  let anchorPx = null;

  return lines.map((line) => {
    // 1) NUEVO: soporte para "||" (continuación con prefijo)
    const dbl = line.indexOf('||');
    if (dbl !== -1) {
      const before = line.slice(0, dbl);        // texto que se conserva
      const after  = line.slice(dbl + 2);       // texto a alinear

      // si no hay ancla previa, lo tratamos como ancla (fallback razonable)
      if (anchorPx === null) {
        anchorPx = ctx.measureText(before).width;
        return escapeHtml(before + after);
      }

      const prefixPx = ctx.measureText(before).width;
      const pad = Math.max(anchorPx - prefixPx, 0);
      const content = after.replace(/^\s+/, '');

      return `${escapeHtml(before)}<span class="indent" style="padding-left:${pad}px">${escapeHtml(content)}</span>`;
    }

    // 2) Comportamiento actual con "|" (ancla o continuación al inicio)
    const pipePos = line.indexOf('|');
    if (pipePos === -1) return escapeHtml(line);

    const isContinuation = /^\s*\|/.test(line);
    const before = line.slice(0, pipePos);
    const after  = line.slice(pipePos + 1);

    if (!isContinuation) {
      // Línea ancla: "por |el dinero"
      anchorPx = ctx.measureText(before).width;
      return escapeHtml(before + after);
    }

    // Línea continuación: "| el cansancio"
    const content = after.replace(/^\s+/, '');
    const pad = anchorPx ?? 0;

    return `<span class="indent" style="padding-left:${pad}px">${escapeHtml(content)}</span>`;
  }).join('\n');
}


function renderPoemWithTitleFromJson(poemText, titleFromJson) {
  const body = (poemText || '').replace(/^\s*\n+/, '').replace(/\s+$/, '');


  const wrapper = document.createElement('div');
  wrapper.className = 'poem';

  if (titleFromJson) {
    const t = document.createElement('div');
    t.className = 'poem-title';
    t.textContent = titleFromJson;
    wrapper.appendChild(t);
  }

  const pre = document.createElement('pre');
  pre.dataset.raw = body;          // guardamos el texto original (con |)
  pre.textContent = body.replaceAll('|', ''); // algo visible “temporal”
  wrapper.appendChild(pre);

  return wrapper;
}


async function loadTodayEntry() {
  const index = await fetch('/textos/archivo.json').then(r => r.json());

  const today = getTodayISO();
  const byDateAsc = [...index].sort((a, b) => a.date.localeCompare(b.date));

// 1) si existe hoy, perfecto
  let chosen = index.find(e => e.date === today);

// 2) si no existe hoy, agarrar la MÁS RECIENTE que sea <= hoy (nunca futura)
  if (!chosen) {
    const upToToday = byDateAsc.filter(e => e.date <= today);
    chosen = upToToday.at(-1);
  }

  const pageDate = document.getElementById('pageDate');
  if (pageDate) pageDate.textContent = formatDate(chosen.date);

  if (!chosen) {
    document.getElementById('poem').innerHTML = '<pre>No hay entradas todavía.</pre>';
    return;
  }

  const raw = await fetch(txtPathFromDate(chosen.date)).then(r => r.text());
  const parsed = parseEntry(raw);

  const myTitle = (chosen.my_poem_title || '').trim(); // del JSON
  const host = document.getElementById('poem');
  host.innerHTML = '';

  const title = (chosen.my_poem_title || '').trim();
  const poemEl = renderPoemWithTitleFromJson(parsed.poem, title);
  host.appendChild(poemEl);

// Ahora que el <pre> ya está en el DOM, medimos con la fuente real:
  const pre = poemEl.querySelector('pre');
  pre.innerHTML = `<span class="poem-lines">${renderPoemWithAnchorIndents(pre.dataset.raw, pre)}</span>`;


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

  const index = await fetch('/textos/archivo.json').then(r => r.json());
  const chosen = index.find(e => e.date === date);

  if (!chosen) {
    document.getElementById('poem').innerHTML = `<pre>No encontré la entrada para ${date}.</pre>`;
    return;
  }

  const raw = await fetch(txtPathFromDate(chosen.date)).then(r => r.text());
  const parsed = parseEntry(raw);

  const host = document.getElementById('poem');
  host.innerHTML = '';

  const title = (chosen.my_poem_title || '').trim();
  const poemEl = renderPoemWithTitleFromJson(parsed.poem, title);
  host.appendChild(poemEl);

// Ahora que el <pre> ya está en el DOM, medimos con la fuente real:
  const pre = poemEl.querySelector('pre');
  pre.innerHTML = `<span class="poem-lines">${renderPoemWithAnchorIndents(pre.dataset.raw, pre)}</span>`;


  document.querySelector('.analysis-poem').textContent = parsed.citedPoem;
  document.querySelector('.analysis-text').innerHTML = textToParagraphs(parsed.analysisText);

  setCitedMeta(chosen);
}

// =========================
//  Tabs: mantener URL ?a=1 sin recargar
// =========================
function wireTabs() {
  const { poemTab, analysisTab } = getTabIds();

  const poemLink = document.getElementById(poemTab);
  const analysisLink = document.getElementById(analysisTab);

  if (poemLink) {
    poemLink.addEventListener('click', (e) => {
      // index.html: es <a href="index.html"> (recarga). Aquí lo evitamos:
      e.preventDefault();
      showPoem();
      setURLForPoem();
    });
  }

  if (analysisLink) {
    analysisLink.addEventListener('click', (e) => {
      e.preventDefault();
      showAnalysis();
      setURLForAnalysis();
    });
  }
}

// =========================
//  Boot
// =========================
document.addEventListener('DOMContentLoaded', () => {
  // 1) aplicar vista (poema vs análisis) desde la URL (?a=1)
  applyViewFromURL();

  // 2) enganchar tabs para que cambien sin recargar
  wireTabs();

  // 3) cargar contenido según la página
  const page = document.body?.dataset?.page;

  if (page === 'passe') {
    loadPastEntry().catch(err => {
      console.error(err);
      document.getElementById('poem').innerHTML = '<pre>Error cargando el texto.</pre>';
    });
  } else if (page === 'index') {
    loadTodayEntry().catch(err => {
      console.error(err);
      document.getElementById('poem').innerHTML = '<pre>Error cargando el texto.</pre>';
    });
  }
});
