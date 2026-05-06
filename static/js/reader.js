let comicId, currentPage, totalPages;

function initReader(id, page, total) {
  comicId = id;
  currentPage = page;
  totalPages = total;

  updateUI();
  preloadPage(currentPage + 1);

  // Hide keyboard hint after 4s
  setTimeout(() => document.getElementById('kb-hint').classList.add('hidden'), 4000);

  // Keyboard navigation
  document.addEventListener('keydown', e => {
    if (e.key === 'ArrowRight' || e.key === ' ') { e.preventDefault(); nextPage(); }
    if (e.key === 'ArrowLeft')                   { e.preventDefault(); prevPage(); }
    if (e.key === 'f' || e.key === 'F')          toggleFullscreen();
    if (e.key === 'Escape')                       closeRating();
  });
}

function updateUI() {
  const img = document.getElementById('page-img');
  img.classList.add('loading');
  img.onload = () => img.classList.remove('loading');
  img.src = `/page/${comicId}/${currentPage}`;

  document.getElementById('cur-page').textContent = currentPage + 1;
  document.getElementById('page-slider').value = currentPage + 1;

  const pct = totalPages > 1 ? ((currentPage / (totalPages - 1)) * 100) : 100;
  document.getElementById('top-progress-fill').style.width = pct + '%';

  saveProgress();
}

function nextPage() {
  if (currentPage < totalPages - 1) {
    currentPage++;
    updateUI();
    preloadPage(currentPage + 1);
  }
}

function prevPage() {
  if (currentPage > 0) {
    currentPage--;
    updateUI();
  }
}

function jumpToPage(page) {
  page = Math.max(0, Math.min(totalPages - 1, parseInt(page)));
  if (page !== currentPage) {
    currentPage = page;
    updateUI();
  }
}

function preloadPage(page) {
  if (page < totalPages) {
    const img = new Image();
    img.src = `/page/${comicId}/${page}`;
  }
}

function saveProgress() {
  fetch(`/api/progress/${comicId}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ page: currentPage })
  });
}

function toggleFullscreen() {
  if (!document.fullscreenElement) {
    document.documentElement.requestFullscreen();
  } else {
    document.exitFullscreen();
  }
}

// ── Rating modal ─────────────────────────────────────────────────────────────

let selectedRating = 0;

function openRating() {
  document.getElementById('rating-modal').classList.remove('hidden');
}

function closeRating() {
  document.getElementById('rating-modal').classList.add('hidden');
}

function selectStar(val) {
  selectedRating = val;
  document.querySelectorAll('.star-pick').forEach((s, i) => {
    s.classList.toggle('selected', i < val);
  });
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

// Close modal on backdrop click
document.addEventListener('click', e => {
  const modal = document.getElementById('rating-modal');
  if (e.target === modal) closeRating();
});
