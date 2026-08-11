(() => {
  const button = document.querySelector("[data-copy-target]");

  if (!button) return;

  const prompt = document.getElementById(button.dataset.copyTarget);
  const status = document.querySelector("[data-copy-status]");

  if (!prompt || !status) return;

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

  let resetTimer;

  button.addEventListener("click", async () => {
    window.clearTimeout(resetTimer);
    button.disabled = true;

    try {
      await copy(prompt.textContent.trim());
      button.textContent = "Copied";
      button.dataset.state = "copied";
      status.textContent = "Agent sign-up prompt copied to the clipboard.";
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
})();
