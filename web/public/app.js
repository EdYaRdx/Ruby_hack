(() => {
  const dropzone = document.querySelector('.dropzone');
  const fileInput = document.querySelector('#spec-file');

  if (dropzone && fileInput) {
    const fileName = dropzone.querySelector('strong');
    const helper = dropzone.querySelector('span:not(.eyebrow):not(.button)');
    const announceFile = (file) => {
      if (!file) return;
      if (fileName) fileName.textContent = file.name;
      if (helper) helper.textContent = 'Файл выбран · нажмите «Анализировать спецификацию»';
      dropzone.classList.add('has-file');
    };

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
        announceFile(event.dataTransfer.files[0]);
      }
    });

    fileInput.addEventListener('change', () => {
      if (fileInput.files.length > 0) {
        announceFile(fileInput.files[0]);
      }
    });
  }

  document.querySelectorAll('.copy-button').forEach((button) => {
    button.addEventListener('click', async () => {
      const target = document.getElementById(button.dataset.copyTarget);
      if (!target || !navigator.clipboard) return;
      try {
        await navigator.clipboard.writeText(target.textContent);
      } catch (_error) {
        return;
      }
      const original = button.textContent;
      button.textContent = 'Скопировано';
      window.setTimeout(() => { button.textContent = original; }, 1200);
    });
  });
})();
