const configuredApiBase = '__API_BASE_URL__';
const apiBase = configuredApiBase.startsWith('__')
  ? `${window.location.protocol}//${window.location.hostname}:3000`
  : configuredApiBase.replace(/\/+$/, '');

const form = document.querySelector('#support-form');
const submitButton = document.querySelector('#support-submit');
const statusRegion = document.querySelector('#support-status');

function setStatus(message, type = '') {
  statusRegion.textContent = message;
  statusRegion.className = `form-status ${type}`.trim();
}

form?.addEventListener('submit', async (event) => {
  event.preventDefault();
  if (!form.reportValidity()) return;

  submitButton.disabled = true;
  submitButton.textContent = 'Enviando…';
  setStatus('Enviando sua solicitação.');

  const data = Object.fromEntries(new FormData(form).entries());
  delete data.consent;

  try {
    const response = await fetch(`${apiBase}/api/v1/support`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(
        payload?.error?.message ||
          'Não foi possível enviar agora. Verifique os dados e tente novamente.',
      );
    }
    form.reset();
    setStatus(
      payload?.data?.message || 'Solicitação enviada. Acompanhe a resposta pelo seu e-mail.',
      'success',
    );
  } catch (error) {
    setStatus(error.message, 'error');
  } finally {
    submitButton.disabled = false;
    submitButton.textContent = 'Enviar solicitação';
  }
});
