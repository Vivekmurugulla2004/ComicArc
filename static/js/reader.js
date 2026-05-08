let comicId, currentPage, totalPages;
let spreadMode   = false;
let verticalMode = false;
let zoomLevel    = 1;
let panX = 0, panY = 0;
let isPanning = false, panStartX, panStartY;
let autoplayMode     = false;
let autoplayTimer    = null;
let progressDebounce = null;

// ── Auto-hide chrome ─────────────────────────────────────────────────────────
let chromeHideTimer  = null;
let chromeVisible    = true;
let mouseThrottle    = null;

function showChrome() {
  if (!chromeVisible) {
    chromeVisible = true;
    document.getElementById('reader-topbar').classList.remove('chrome-hidden');
    document.getElementById('reader-bottombar').classList.remove('chrome-hidden');
    document.getElementById('top-progress').classList.remove('chrome-hidden');
  }
  resetChromeTimer();
}

function hideChrome() {
  chromeVisible = false;
  document.getElementById('reader-topbar').classList.add('chrome-hidden');
  document.getElementById('reader-bottombar').classList.add('chrome-hidden');
  document.getElementById('top-progress').classList.add('chrome-hidden');
}

function resetChromeTimer() {
  clearTimeout(chromeHideTimer);
  chromeHideTimer = setTimeout(hideChrome, 3000);
}

function toggleChrome() {
  if (chromeVisible) { clearTimeout(chromeHideTimer); hideChrome(); }
  else showChrome();
}

function initReader(id, page, total) {
  comicId     = id;
  currentPage = page;
  totalPages  = total;

  updateUI();
  preloadPage(currentPage + 1);
  resetChromeTimer();

  document.addEventListener('mousemove', () => {
    if (mouseThrottle) return;
    mouseThrottle = setTimeout(() => { mouseThrottle = null; }, 100);
    showChrome();
  });

  // Keyboard navigation
  document.addEventListener('keydown', e => {
    if (e.target.tagName === 'TEXTAREA' || e.target.tagName === 'INPUT') return;
    showChrome();
    if (e.key === 'ArrowRight' || e.key === ' ') { e.preventDefault(); nextPage(); }
    if (e.key === 'ArrowLeft')                   { e.preventDefault(); prevPage(); }
    if (e.key === 'ArrowDown' && verticalMode)   { e.preventDefault(); scrollBy(0, window.innerHeight * 0.8); }
    if (e.key === 'ArrowUp'   && verticalMode)   { e.preventDefault(); scrollBy(0, -window.innerHeight * 0.8); }
    if (e.key === 'd' || e.key === 'D')          toggleSpread();
    if (e.key === 'v' || e.key === 'V')          toggleVertical();
    if (e.key === 'z' || e.key === 'Z')          setZoom(zoomLevel > 1 ? 1 : 2.5);
    if (e.key === 'a' || e.key === 'A')          toggleAutoplay();
    if (e.key === 'm' || e.key === 'M')          toggleChrome();
    if (e.key === 'Home')                        { e.preventDefault(); jumpToPage(0); }
    if (e.key === 'End')                         { e.preventDefault(); jumpToPage(totalPages - 1); }
    if (e.key === '?')                           openHelp();
    if (e.key === 'Escape') {
      if (zoomLevel > 1) setZoom(1);
      else if (autoplayMode) toggleAutoplay();
      else if (!document.getElementById('help-modal').classList.contains('hidden')) closeHelp();
      else closeRating();
    }
  });

  // Touch swipe
  let touchStartX = 0, touchStartY = 0;
  const pageArea = document.getElementById('page-area');
  pageArea.addEventListener('touchstart', e => {
    touchStartX = e.changedTouches[0].clientX;
    touchStartY = e.changedTouches[0].clientY;
  }, { passive: true });
  pageArea.addEventListener('touchend', e => {
    if (verticalMode || zoomLevel > 1) return;
    const dx = e.changedTouches[0].clientX - touchStartX;
    const dy = e.changedTouches[0].clientY - touchStartY;
    if (Math.abs(dx) > Math.abs(dy) && Math.abs(dx) > 40) {
      dx < 0 ? nextPage() : prevPage();
    }
  }, { passive: true });

  // Zoom — mouse pan
  const display = document.getElementById('page-display');
  display.addEventListener('mousedown', e => {
    if (zoomLevel <= 1) return;
    isPanning  = true;
    panStartX  = e.clientX - panX;
    panStartY  = e.clientY - panY;
    display.style.cursor = 'grabbing';
    e.preventDefault();
  });
  document.addEventListener('mousemove', e => {
    if (!isPanning) return;
    panX = e.clientX - panStartX;
    panY = e.clientY - panStartY;
    applyZoom();
  });
  document.addEventListener('mouseup', () => {
    if (isPanning) { isPanning = false; display.style.cursor = 'grab'; }
  });

  // Zoom — scroll wheel (paged mode only)
  pageArea.addEventListener('wheel', e => {
    if (verticalMode) return;
    e.preventDefault();
    setZoom(zoomLevel + (e.deltaY < 0 ? 0.25 : -0.25));
  }, { passive: false });
}

// ── Paged navigation ─────────────────────────────────────────────────────────

function updateUI() {
  const img = document.getElementById('page-img');
  img.classList.add('loading');
  img.onload = () => img.classList.remove('loading');
  img.src = `/page/${comicId}/${currentPage}`;

  const imgB = document.getElementById('page-img-b');
  if (spreadMode && currentPage + 1 < totalPages) {
    imgB.src = `/page/${comicId}/${currentPage + 1}`;
    imgB.style.display = '';
  } else {
    imgB.style.display = 'none';
  }

  document.getElementById('cur-page').textContent = currentPage + 1;
  const slider = document.getElementById('page-slider');
  if (slider) slider.value = currentPage + 1;
  const pct = totalPages > 1 ? (currentPage / (totalPages - 1) * 100) : 100;
  document.getElementById('top-progress-fill').style.width = pct + '%';
  saveProgress();
}

function nextPage() {
  if (verticalMode) return;
  const step = spreadMode ? 2 : 1;
  if (currentPage < totalPages - 1) {
    currentPage = Math.min(currentPage + step, totalPages - 1);
    if (zoomLevel > 1) setZoom(1); // reset zoom when turning page
    updateUI();
    preloadPage(currentPage + step);
    resetAutoplayTimer();
  } else {
    // Fall back to reading the DOM link href in case the JS variable is stale
    const url = nextComicUrl || document.querySelector('.run-nav-next')?.href || null;
    if (url) {
      stopAutoplayTimer();
      location.href = url;
    } else if (autoplayMode) {
      // End of last comic in run — stop autoplay
      autoplayMode = false;
      stopAutoplayTimer();
      const btn = document.getElementById('autoplay-btn');
      if (btn) btn.classList.remove('active');
    }
  }
}

function prevPage() {
  if (verticalMode) return;
  const step = spreadMode ? 2 : 1;
  if (currentPage > 0) {
    currentPage = Math.max(currentPage - step, 0);
    updateUI();
    resetAutoplayTimer();
  } else {
    const url = prevComicUrl || document.querySelector('.run-nav-prev')?.href || null;
    if (url) {
      stopAutoplayTimer();
      location.href = url;
    }
  }
}

function jumpToPage(page) {
  page = Math.max(0, Math.min(totalPages - 1, parseInt(page)));
  if (verticalMode) {
    const target = document.querySelector(`.scroll-page[data-page="${page}"]`);
    if (target) target.scrollIntoView({ behavior: 'smooth' });
  } else if (page !== currentPage) {
    currentPage = page;
    updateUI();
    resetAutoplayTimer();
  }
}

function preloadPage(page) {
  if (page < totalPages) new Image().src = `/page/${comicId}/${page}`;
}

function saveProgress() {
  clearTimeout(progressDebounce);
  progressDebounce = setTimeout(_flushProgress, 1500);
}

function _flushProgress() {
  clearTimeout(progressDebounce);
  fetch(`/api/progress/${comicId}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ page: currentPage })
  });
}

window.addEventListener('beforeunload', _flushProgress);

// ── Autoplay ──────────────────────────────────────────────────────────────────

function toggleAutoplay() {
  autoplayMode = !autoplayMode;
  const btn = document.getElementById('autoplay-btn');
  if (btn) btn.classList.toggle('active', autoplayMode);
  if (autoplayMode) {
    startAutoplayTimer();
  } else {
    stopAutoplayTimer();
  }
}

function startAutoplayTimer() {
  clearTimeout(autoplayTimer);
  const fill = document.getElementById('autoplay-fill');
  if (fill) {
    fill.classList.remove('ticking');
    void fill.offsetWidth; // force reflow so animation restarts
    fill.classList.add('ticking');
  }
  autoplayTimer = setTimeout(() => {
    if (autoplayMode) nextPage();
  }, 10000);
}

function stopAutoplayTimer() {
  clearTimeout(autoplayTimer);
  autoplayTimer = null;
  const fill = document.getElementById('autoplay-fill');
  if (fill) fill.classList.remove('ticking');
}

function resetAutoplayTimer() {
  if (autoplayMode) startAutoplayTimer();
}

// ── Spread mode ───────────────────────────────────────────────────────────────

function toggleSpread() {
  if (verticalMode) return;
  spreadMode = !spreadMode;
  document.getElementById('page-display').classList.toggle('spread', spreadMode);
  document.getElementById('spread-btn').classList.toggle('active', spreadMode);
  updateUI();
}

// ── Vertical scroll mode ──────────────────────────────────────────────────────

function toggleVertical() {
  verticalMode = !verticalMode;
  const btn       = document.getElementById('vertical-btn');
  const scrollEl  = document.getElementById('scroll-container');
  const pageDisp  = document.getElementById('page-display');
  const prevZone  = document.getElementById('prev-zone');
  const nextZone  = document.getElementById('next-zone');
  const bottomBar = document.getElementById('reader-bottombar');

  btn.classList.toggle('active', verticalMode);

  if (verticalMode) {
    pageDisp.style.display  = 'none';
    prevZone.style.display  = 'none';
    nextZone.style.display  = 'none';
    scrollEl.style.display  = 'block';
    bottomBar.style.display = 'none';
    stopAutoplayTimer(); // autoplay not supported in vertical mode
    setZoom(1);
    buildScrollView();
  } else {
    scrollEl.style.display  = 'none';
    pageDisp.style.display  = '';
    prevZone.style.display  = '';
    nextZone.style.display  = '';
    bottomBar.style.display = '';
    updateUI();
    resetAutoplayTimer(); // restart countdown if autoplay was on before vertical mode
  }
}

function buildScrollView() {
  const container = document.getElementById('scroll-container');
  container.innerHTML = '';

  for (let i = 0; i < totalPages; i++) {
    const wrap = document.createElement('div');
    wrap.className  = 'scroll-page';
    wrap.dataset.page = i;

    const img = document.createElement('img');
    img.className  = 'scroll-page-img';
    img.dataset.src = `/page/${comicId}/${i}`;
    img.alt        = `Page ${i + 1}`;
    wrap.appendChild(img);
    container.appendChild(wrap);
  }

  const current = container.querySelectorAll('.scroll-page')[currentPage];
  if (current) current.scrollIntoView();

  const io = new IntersectionObserver(entries => {
    entries.forEach(entry => {
      const img = entry.target.querySelector('img');
      if (entry.isIntersecting) {
        if (img && img.dataset.src) {
          img.src = img.dataset.src;
          delete img.dataset.src;
        }
        const p = parseInt(entry.target.dataset.page);
        if (p !== currentPage) {
          currentPage = p;
          document.getElementById('cur-page').textContent = p + 1;
          const slider = document.getElementById('page-slider');
          if (slider) slider.value = p + 1;
          const pct = totalPages > 1 ? (p / (totalPages - 1) * 100) : 100;
          document.getElementById('top-progress-fill').style.width = pct + '%';
          saveProgress();
        }
      }
    });
  }, { threshold: 0.5, root: container });

  container.querySelectorAll('.scroll-page').forEach(p => io.observe(p));
}

// ── Zoom / pan ────────────────────────────────────────────────────────────────

function setZoom(level) {
  zoomLevel = Math.max(1, Math.min(5, level));
  applyZoom();
  const btn = document.getElementById('zoom-btn');
  if (btn) {
    btn.classList.toggle('active', zoomLevel > 1);
    btn.title = zoomLevel > 1 ? `Zoom ${zoomLevel.toFixed(1)}× (Z)` : 'Zoom (Z)';
  }
}

function applyZoom() {
  const display = document.getElementById('page-display');
  if (zoomLevel <= 1) {
    panX = panY = 0;
    display.style.transform  = '';
    display.style.cursor     = '';
    display.style.transformOrigin = '';
  } else {
    display.style.transform  = `scale(${zoomLevel}) translate(${panX / zoomLevel}px, ${panY / zoomLevel}px)`;
    display.style.cursor     = isPanning ? 'grabbing' : 'grab';
    display.style.transformOrigin = 'center center';
  }
}


// ── Rating modal ──────────────────────────────────────────────────────────────

let selectedRating = 0;

function openHelp() {
  document.getElementById('help-modal').classList.remove('hidden');
  stopAutoplayTimer();
}
function closeHelp() {
  document.getElementById('help-modal').classList.add('hidden');
  resetAutoplayTimer();
}

function openRating() {
  document.getElementById('rating-modal').classList.remove('hidden');
  stopAutoplayTimer();
}
function closeRating() {
  document.getElementById('rating-modal').classList.add('hidden');
  resetAutoplayTimer();
}

function selectStar(val) {
  selectedRating = val;
  document.querySelectorAll('.star-pick').forEach((s, i) => s.classList.toggle('selected', i < val));
}

function submitRating(id) {
  if (!selectedRating) { closeRating(); return; }
  const review = document.getElementById('review-text').value;
  fetch(`/api/rate/${id}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ rating: selectedRating, review })
  }).then(() => closeRating());
}

document.addEventListener('click', e => {
  if (e.target === document.getElementById('rating-modal')) closeRating();
});
