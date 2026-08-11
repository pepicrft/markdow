(() => {
  const host = document.querySelector("meta[name='smolanalytics-host']")?.content?.replace(/\/$/, "")
  const writeKey = document.querySelector("meta[name='smolanalytics-write-key']")?.content

  if (!host || !writeKey) return

  let ready = false
  const pendingEvents = []

  const track = event => {
    if (!event) return

    if (ready) {
      window.smolanalytics?.track(event)
    } else {
      pendingEvents.push(event)
    }
  }

  document.addEventListener("click", event => {
    const target = event.target.closest("[data-analytics-event]")
    if (target) track(target.dataset.analyticsEvent)
  })

  const sdk = document.createElement("script")
  sdk.src = `${host}/sdk.js`
  sdk.async = true
  sdk.addEventListener("load", () => {
    window.smolanalytics?.init(writeKey, {host, anonymous: true})
    ready = true
    pendingEvents.splice(0).forEach(event => window.smolanalytics?.track(event))
    track(document.body.dataset.analyticsPageEvent)
  })
  sdk.addEventListener("error", () => {
    console.warn("smolanalytics: the browser client could not be loaded")
  })
  document.head.appendChild(sdk)
})()
