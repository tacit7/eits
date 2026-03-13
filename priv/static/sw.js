self.addEventListener("push", (event) => {
  let data = {};
  try {
    data = event.data.json();
  } catch (_) {
    data = { title: event.data ? event.data.text() : "Eye in the Sky", body: "" };
  }

  const title = data.title || "Eye in the Sky";
  const options = {
    body: data.body || "",
    icon: data.icon || "/images/logo.svg",
    badge: "/images/logo.svg",
    data: data,
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil(clients.openWindow("/"));
});
