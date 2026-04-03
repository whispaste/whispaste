(function () {
  // Hide feedback/Rate Us for Store installs
  if (typeof window._getInstallSource === 'function') {
    window._getInstallSource().then(function (source) {
      if (source === 'msix') {
        var rateUs = document.getElementById('rateUsSection');
        if (rateUs) rateUs.style.display = 'none';
      }
    });
  }

  let selectedRating = 0;

  function showFeedbackError(msg) {
    const el = document.getElementById('feedback-error');
    if (el) {
      el.textContent = msg;
      el.hidden = false;
    }
  }

  function hideFeedbackError() {
    const el = document.getElementById('feedback-error');
    if (el) {
      el.hidden = true;
    }
  }

  document.addEventListener('DOMContentLoaded', function () {
    const stars = document.querySelectorAll('.star-btn');
    const textArea = document.getElementById('feedback-text');
    const charCount = document.getElementById('feedback-chars');
    const submitBtn = document.getElementById('feedback-submit');
    const cancelBtn = document.getElementById('feedback-cancel');
    const successDiv = document.getElementById('feedback-success');

    if (!stars.length || !submitBtn) return;

    stars.forEach(function (star) {
      star.addEventListener('click', function () {
        selectedRating = parseInt(this.dataset.rating);
        stars.forEach(function (s) {
          const r = parseInt(s.dataset.rating);
          s.classList.toggle('selected', r <= selectedRating);
        });
        submitBtn.disabled = false;
      });

      star.addEventListener('mouseenter', function () {
        const hoverRating = parseInt(this.dataset.rating);
        stars.forEach(function (s) {
          const r = parseInt(s.dataset.rating);
          s.classList.toggle('active', r <= hoverRating);
        });
      });

      star.addEventListener('mouseleave', function () {
        stars.forEach(function (s) { s.classList.remove('active'); });
      });
    });

    if (textArea && charCount) {
      textArea.addEventListener('input', function () {
        charCount.textContent = this.value.length;
      });
    }

    submitBtn.addEventListener('click', async function () {
      if (selectedRating < 1) return;
      hideFeedbackError();
      submitBtn.disabled = true;
      submitBtn.textContent = '…';

      let text = (textArea ? textArea.value : '').trim().slice(0, 500);

      try {
        const result = await window._submitFeedback(selectedRating, text);
        if (result) {
          submitBtn.disabled = false;
          submitBtn.textContent = t('feedback.submit');
          showFeedbackError(result);
          return;
        }
        // Success — hide form, show thank-you
        var starsDiv = document.querySelector('.feedback-stars');
        if (starsDiv) starsDiv.classList.add('hidden');
        if (textArea) textArea.classList.add('hidden');
        var charDiv = document.querySelector('.feedback-char-count');
        if (charDiv) charDiv.classList.add('hidden');
        var privacyP = document.querySelector('.feedback-privacy');
        if (privacyP) privacyP.classList.add('hidden');
        var actionsDiv = document.querySelector('.feedback-actions');
        if (actionsDiv) actionsDiv.classList.add('hidden');
        hideFeedbackError();
        if (successDiv) successDiv.classList.remove('hidden');
      } catch (err) {
        showFeedbackError(String(err));
        submitBtn.disabled = false;
        submitBtn.textContent = t('feedback.submit');
      }
    });

    if (cancelBtn) {
      cancelBtn.addEventListener('click', function () {
        switchPage('history');
      });
    }
  });
})();
