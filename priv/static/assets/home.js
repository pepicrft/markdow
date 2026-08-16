(() => {
  const copyWithSelection = (text) => {
    const input = document.createElement("textarea");

    input.value = text;
    input.setAttribute("readonly", "");
    input.style.position = "fixed";
    input.style.opacity = "0";
    document.body.appendChild(input);
    input.select();

    const copied = document.execCommand("copy");
    input.remove();

    if (!copied) throw new Error("The browser rejected the copy operation.");
  };

  const copy = async (text) => {
    if (navigator.clipboard?.writeText) {
      try {
        await navigator.clipboard.writeText(text);
        return;
      } catch (_error) {
        // Some self-hosted origins do not grant the asynchronous clipboard API.
      }
    }

    copyWithSelection(text);
  };

  document.querySelectorAll("[data-copy-target]").forEach((button) => {
    const prompt = document.getElementById(button.dataset.copyTarget);
    const status = button.parentElement?.querySelector("[data-copy-status]");

    if (!prompt || !status) return;

    let resetTimer;

    button.addEventListener("click", async () => {
      window.clearTimeout(resetTimer);
      button.disabled = true;

      try {
        await copy(prompt.textContent.trim());
        button.textContent = "Copied";
        button.dataset.state = "copied";
        status.textContent = button.dataset.copySuccess;
      } catch (_error) {
        button.textContent = "Try again";
        button.dataset.state = "error";
        status.textContent = "The prompt could not be copied. Select and copy it manually.";
      } finally {
        button.disabled = false;
        resetTimer = window.setTimeout(() => {
          button.textContent = "Copy";
          delete button.dataset.state;
        }, 2_000);
      }
    });
  });
})();
