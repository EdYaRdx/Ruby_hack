(() => {
  const dropzone = document.querySelector('.dropzone');
  const fileInput = document.querySelector('#spec-file');

  if (dropzone && fileInput) {
    ['dragenter', 'dragover'].forEach((eventName) => {
      dropzone.addEventListener(eventName, (event) => {
        event.preventDefault();
        dropzone.classList.add('dragging');
      });
    });

    ['dragleave', 'drop'].forEach((eventName) => {
      dropzone.addEventListener(eventName, (event) => {
        event.preventDefault();
        dropzone.classList.remove('dragging');
      });
    });

    dropzone.addEventListener('drop', (event) => {
      if (event.dataTransfer.files.length > 0) {
        fileInput.files = event.dataTransfer.files;
        dropzone.querySelector('strong').textContent = event.dataTransfer.files[0].name;
      }
    });

    fileInput.addEventListener('change', () => {
      if (fileInput.files.length > 0) {
        dropzone.querySelector('strong').textContent = fileInput.files[0].name;
      }
    });
  }

  document.querySelectorAll('.copy-button').forEach((button) => {
    button.addEventListener('click', async () => {
      const target = document.getElementById(button.dataset.copyTarget);
      if (!target || !navigator.clipboard) return;
      await navigator.clipboard.writeText(target.textContent);
      const original = button.textContent;
      button.textContent = 'Скопировано';
      window.setTimeout(() => { button.textContent = original; }, 1200);
    });
  });
})();
