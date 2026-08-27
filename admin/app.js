import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const config = window.PCBOX_ADMIN_CONFIG || {};
const supabase =
  config.supabaseUrl && config.supabasePublishableKey
    ? createClient(config.supabaseUrl, config.supabasePublishableKey)
    : null;
const app = document.querySelector("#app");
const toastRegion = document.querySelector("#toast");
const state = {
  user: null,
  section: "overview",
  raffles: [],
  selectedRaffleId: "",
  registrations: [],
  registrationSearch: "",
  pendingSearch: "",
  loading: false,
};

function escapeHtml(value = "") {
  return String(value).replace(
    /[&<>'"]/g,
    (character) =>
      ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        "'": "&#039;",
        '"': "&quot;",
      })[character],
  );
}
function money(value) {
  return `S/ ${Number(value || 0).toFixed(2)}`;
}
function date(value) {
  return value
    ? new Date(value).toLocaleDateString("es-PE", { dateStyle: "medium" })
    : "Por anunciar";
}
function toast(message, type = "") {
  const item = document.createElement("div");
  item.className = `toast ${type}`;
  item.textContent = message;
  toastRegion.append(item);
  setTimeout(() => item.remove(), 4000);
}
function statusLabel(value) {
  return value === "aprobado"
    ? "Aprobado"
    : value === "rechazado"
      ? "Rechazado"
      : "En revisión";
}
function statusClass(value) {
  return value === "aprobado"
    ? "approved"
    : value === "rechazado"
      ? "rejected"
      : "pending";
}

function renderLogin(message = "") {
  app.innerHTML = `<main class="login-page"><section class="card login-card"><div class="brand"><span class="brand-mark">PB</span><span>PC <span style="color:var(--primary)">BOX</span><small>Admin</small></span></div><h1>Panel administrador</h1><p>Gestiona sorteos, comprobantes, tickets y ganadores desde un espacio seguro.</p>${message ? `<div class="error-box" style="margin-top:17px">${escapeHtml(message)}</div>` : ""}<form class="login-form" id="login-form"><label class="form-label">Correo<input class="field" name="email" type="email" autocomplete="username" required /></label><label class="form-label">Contraseña<input class="field" name="password" type="password" autocomplete="current-password" required /></label><button class="button" type="submit">Ingresar al dashboard</button></form></section></main>`;
  document.querySelector("#login-form").addEventListener("submit", signIn);
}

function renderDashboard() {
  const raffle = state.raffles.find(
    (item) => item.id === state.selectedRaffleId,
  );
  const approved = state.registrations.filter(
    (item) => item.status === "aprobado",
  ).length;
  const pending = state.registrations.filter(
    (item) => item.status === "pendiente",
  ).length;
  const ticketsAssigned = state.registrations.reduce(
    (total, item) => total + (item.tickets?.length || 0),
    0,
  );
  app.innerHTML = `<div class="shell"><aside class="sidebar"><a class="brand" href="#"><span class="brand-mark">PB</span><span>PC <span style="color:var(--primary)">BOX</span><small>Admin</small></span></a><p class="admin-label">Administración</p><nav class="side-nav"><button class="${state.section === "overview" ? "active" : ""}" data-section="overview">▦ Resumen</button><button class="${state.section === "registrations" ? "active" : ""}" data-section="registrations">✓ Inscripciones</button><button class="${state.section === "raffles" ? "active" : ""}" data-section="raffles">◇ Sorteos</button><button class="${state.section === "winners" ? "active" : ""}" data-section="winners">★ Ganadores</button></nav><div class="sidebar-footer">Sesión protegida con Supabase Auth.<br />Solo usuarios con rol admin.</div></aside><div class="main"><header class="topbar"><h1>${state.section === "overview" ? "Resumen" : state.section === "registrations" ? "Inscripciones" : state.section === "raffles" ? "Sorteos" : "Ganadores"}</h1><div class="user-actions"><span>${escapeHtml(state.user.email || "Administrador")}</span><button class="button secondary small" id="logout">Cerrar sesión</button></div></header><main class="content">${renderSection(raffle, approved, pending, ticketsAssigned)}</main></div></div>`;
  document.querySelectorAll("[data-section]").forEach((button) =>
    button.addEventListener("click", () => {
      state.section = button.dataset.section;
      renderDashboard();
    }),
  );
  document.querySelector("#logout").addEventListener("click", signOut);
  bindSectionEvents();
}

function renderSection(raffle, approved, pending, ticketsAssigned) {
  if (state.section === "registrations") return renderRegistrations(raffle);
  if (state.section === "raffles") return renderRaffles();
  if (state.section === "winners") return renderWinners(raffle);
  return `<section class="cards"><article class="card stat"><p>Sorteos registrados</p><strong>${state.raffles.length}</strong></article><article class="card stat"><p>Participantes inscritos</p><strong>${approved}</strong></article><article class="card stat"><p>En revisión</p><strong style="color:var(--yellow)">${pending}</strong></article><article class="card stat"><p>Tickets asignados</p><strong style="color:var(--green)">${ticketsAssigned}</strong></article></section><div class="toolbar"><div><h2>Pendientes por aprobar</h2><p>${raffle ? `Revisa las solicitudes de ${escapeHtml(raffle.title)}.` : "Selecciona un sorteo para comenzar."}</p></div><div class="registration-filters"><label class="filter">Sorteo<select class="field" id="raffle-filter">${raffleOptions()}</select></label><label class="filter registration-search"><span>Buscar por DNI</span><input class="field" id="pending-search" type="search" inputmode="numeric" maxlength="8" value="${escapeHtml(state.pendingSearch)}" placeholder="DNI del participante" autocomplete="off" /></label></div></div><div id="pending-registrations-results">${renderRegistrationTable(raffle, "pending", state.pendingSearch)}</div>`;
}

function raffleOptions() {
  return `<option value="">Selecciona un sorteo</option>${state.raffles.map((raffle) => `<option value="${raffle.id}" ${raffle.id === state.selectedRaffleId ? "selected" : ""}>${escapeHtml(raffle.title)}</option>`).join("")}`;
}
function renderRegistrations(raffle) {
  return `<div class="toolbar registrations-toolbar"><div><h2>Participantes inscritos</h2><p>Consulta únicamente las inscripciones aprobadas, un ticket por tarjeta.</p></div><div class="registration-filters"><label class="filter">Sorteo<select class="field" id="raffle-filter">${raffleOptions()}</select></label><label class="filter registration-search">Buscar participante<input class="field" id="registration-search" type="search" value="${escapeHtml(state.registrationSearch)}" placeholder="Nombre, DNI o ticket" autocomplete="off" /></label></div></div><div id="registered-tickets-results">${renderApprovedTickets(raffle)}</div>`;
}
function renderApprovedTickets(raffle) {
  if (!raffle)
    return `<div class="card empty">Selecciona un sorteo para ver sus inscritos.</div>`;
  const query = state.registrationSearch.trim().toLocaleLowerCase("es-PE");
  const approvedRegistrations = state.registrations.filter(
    (item) => item.status === "aprobado",
  );
  const tickets = approvedRegistrations
    .flatMap((item) =>
      (item.tickets || []).map((ticket) => ({
        item,
        ticket: String(ticket),
      })),
    )
    .filter(({ item, ticket }) => {
      if (!query) return true;
      return [item.full_name, item.dni, item.phone, item.email, ticket]
        .filter(Boolean)
        .some((value) =>
          String(value).toLocaleLowerCase("es-PE").includes(query),
        );
    })
    .sort((a, b) => {
      const ticketA = Number.parseInt(a.ticket, 10);
      const ticketB = Number.parseInt(b.ticket, 10);
      return ticketA - ticketB || String(a.item.full_name).localeCompare(String(b.item.full_name), "es");
    });
  if (!tickets.length)
    return `<div class="card empty">${query ? "No encontramos participantes o tickets con esa búsqueda." : "No hay participantes inscritos en este sorteo."}</div>`;
  return `<div class="participant-ticket-grid">${tickets
    .map(
      ({ item, ticket }) =>
        `<article class="participant-ticket-card"><div class="participant-ticket-heading"><div><span class="participant-ticket-label">Ticket asignado</span><strong class="participant-ticket-number">#${escapeHtml(ticket)}</strong></div><span class="status approved">Aprobado</span></div><div class="participant-ticket-info"><div><span>Participante</span><strong>${escapeHtml(item.full_name)}</strong></div><div><span>DNI</span><strong>${escapeHtml(item.dni)}</strong></div><div><span>Celular</span><strong>${escapeHtml(item.phone || "-")}</strong></div><div><span>Monto registrado</span><strong>${money(item.amount)}</strong></div></div><div class="participant-ticket-footer"><span>Registrado el ${date(item.created_at)}</span><div class="actions"><button class="button secondary small" data-action="receipt" data-path="${escapeHtml(item.receipt_url || "")}">Ver comprobante</button><button class="button danger small" data-action="delete" data-id="${item.id}">Eliminar inscripción</button></div></div></article>`,
    )
    .join("")}</div>`;
}
function renderRegistrationTable(raffle, view = "all", search = "") {
  if (!raffle)
    return `<div class="card empty">Selecciona un sorteo para ver sus inscritos.</div>`;
  const query = String(search || "").replace(/\D/g, "").slice(0, 8);
  const visibleRegistrations = state.registrations.filter((item) =>
    view === "pending"
      ? item.status === "pendiente"
      : view === "approved"
        ? item.status === "aprobado"
        : true,
  ).filter((item) => {
    if (view !== "pending" || !query) return true;
    return String(item.dni || "").includes(query);
  );
  if (!visibleRegistrations.length)
    return `<div class="card empty">${view === "pending" && query ? "No encontramos solicitudes pendientes con ese DNI." : view === "pending" ? "No hay solicitudes pendientes de aprobación." : view === "approved" ? "No hay participantes inscritos en este sorteo." : "No hay inscripciones para este sorteo."}</div>`;
  return `<div class="table-wrap"><table><thead><tr><th>Participante</th><th>Contacto</th><th>Tickets</th><th>Monto</th><th>Estado</th><th>Fecha</th><th>Acciones</th></tr></thead><tbody>${visibleRegistrations.map((item) => `<tr><td><div class="name">${escapeHtml(item.full_name)}</div><div class="sub">DNI ${escapeHtml(item.dni)}</div></td><td><div>${escapeHtml(item.phone || "-")}</div><div class="sub">${escapeHtml(item.email || "Sin correo")}</div></td><td>${item.quantity}</td><td>${money(item.amount)}</td><td><span class="status ${statusClass(item.status)}">${statusLabel(item.status)}</span>${item.tickets?.length ? `<div class="sub">#${item.tickets.join(", #")}</div>` : ""}</td><td>${date(item.created_at)}</td><td><div class="actions"><button class="button secondary small" data-action="receipt" data-path="${escapeHtml(item.receipt_url || "")}">Ver comprobante</button>${view === "pending" ? `<button class="button success small" data-action="approve" data-id="${item.id}">Aprobar</button><button class="button danger small" data-action="reject" data-id="${item.id}">Rechazar</button>` : ""}<button class="button danger small" data-action="delete" data-id="${item.id}">Eliminar</button></div></td></tr>`).join("")}</tbody></table></div>`;
}

function renderRaffles() {
  return `<div class="toolbar"><div><h2>Administrar sorteos</h2><p>Crea sorteos y define sus premios para la web pública.</p></div><button class="button" data-action="show-create">+ Nuevo sorteo</button></div><div class="raffles-admin">${state.raffles.map((raffle) => `<article class="card raffle-admin"><h3>${escapeHtml(raffle.title)}</h3><p>${escapeHtml(raffle.description || "Sin descripción")}</p><div class="row"><span>Estado</span><strong>${escapeHtml(raffle.status)}</strong></div><div class="row"><span>Ticket</span><strong>${money(raffle.ticket_price)}</strong></div><div class="row"><span>Fecha</span><strong>${date(raffle.draw_date)}</strong></div><ul class="prizes">${(raffle.prizes || []).map((prize) => `<li><span class="prize-dot">${prize.position}</span>${escapeHtml(prize.name)}</li>`).join("")}</ul></article>`).join("") || `<div class="card empty">Aún no hay sorteos.</div>`}</div>`;
}

function renderWinners(raffle) {
  return `<div class="toolbar"><div><h2>Designar ganadores</h2><p>Selecciona un sorteo y ejecuta el sorteo de cada premio.</p></div><label class="filter">Sorteo<select class="field" id="raffle-filter">${raffleOptions()}</select></label></div>${raffle ? `<div class="draw-list">${(raffle.prizes || []).map((prize) => `<div class="draw-item"><div><strong>${escapeHtml(prize.name)}</strong><br /><span>${prize.winner_ticket_number ? `Ganador: #${prize.winner_ticket_number} · ${escapeHtml(prize.winner_name || "")}` : "Pendiente de sorteo"}</span></div>${prize.winner_ticket_number ? `<span class="status approved">Publicado</span>` : `<button class="button small" data-action="draw" data-id="${prize.id}">Sortear premio</button>`}</div>`).join("")}</div>` : `<div class="card empty">Selecciona un sorteo para ver sus premios.</div>`}`;
}

function bindSectionEvents() {
  const filter = document.querySelector("#raffle-filter");
  if (filter)
    filter.addEventListener("change", async (event) => {
      state.selectedRaffleId = event.target.value;
      state.registrationSearch = "";
      state.pendingSearch = "";
      await loadRegistrations();
      renderDashboard();
    });
  bindActionButtons();
  const pendingSearch = document.querySelector("#pending-search");
  if (pendingSearch)
    pendingSearch.addEventListener("input", (event) => {
      state.pendingSearch = event.target.value.replace(/\D/g, "").slice(0, 8);
      event.target.value = state.pendingSearch;
      const raffle = state.raffles.find(
        (item) => item.id === state.selectedRaffleId,
      );
      const results = document.querySelector("#pending-registrations-results");
      if (results) results.innerHTML = renderRegistrationTable(raffle, "pending", state.pendingSearch);
      bindActionButtons(results || document);
    });
  const search = document.querySelector("#registration-search");
  if (search)
    search.addEventListener("input", (event) => {
      state.registrationSearch = event.target.value;
      const raffle = state.raffles.find(
        (item) => item.id === state.selectedRaffleId,
      );
      const results = document.querySelector("#registered-tickets-results");
      if (!results) return;
      results.innerHTML = renderApprovedTickets(raffle);
      bindActionButtons(results);
    });
  const createForm = document.querySelector("#create-raffle-form");
  if (createForm) createForm.addEventListener("submit", createRaffle);
}

function bindActionButtons(root = document) {
  root
    .querySelectorAll("[data-action]")
    .forEach((button) =>
      button.addEventListener("click", () => handleAction(button)),
    );
}

async function handleAction(button) {
  const action = button.dataset.action;
  try {
    if (action === "receipt") return viewReceipt(button.dataset.path);
    if (action === "show-create") return showCreateModal();
    if (action === "approve") {
      if (!confirm("¿Aprobar esta inscripción y asignar sus tickets?")) return;
      await rpc("aprobar_inscripcion", {
        p_registration_id: button.dataset.id,
        p_nota: null,
      });
      toast("Inscripción aprobada y tickets asignados.", "success");
    }
    if (action === "reject") {
      if (!confirm("¿Rechazar esta inscripción?")) return;
      await rpc("rechazar_inscripcion", {
        p_registration_id: button.dataset.id,
        p_nota: "Rechazado desde el dashboard.",
      });
      toast("Inscripción rechazada.", "success");
    }
    if (action === "delete") {
      if (
        !confirm(
          "Esta acción eliminará la inscripción y sus tickets. ¿Continuar?",
        )
      )
        return;
      await rpc("eliminar_inscripcion", {
        p_registration_id: button.dataset.id,
      });
      toast("Inscripción eliminada.", "success");
    }
    if (action === "draw") {
      if (!confirm("¿Ejecutar el sorteo aleatorio para este premio?")) return;
      const result = await rpc("sortear_ganador", {
        p_prize_id: button.dataset.id,
      });
      toast(
        `Ganador asignado: #${result?.[0]?.ticket_number || "-"}.`,
        "success",
      );
    }
    await loadRaffles();
    await loadRegistrations();
    renderDashboard();
  } catch (error) {
    toast(error.message, "error");
  }
}

async function rpc(fn, params) {
  const { data, error } = await supabase.rpc(fn, params);
  if (error) throw error;
  return data;
}
async function viewReceipt(path) {
  if (!path) return toast("Esta inscripción no tiene comprobante.", "error");
  const { data, error } = await supabase.storage
    .from("comprobantes")
    .createSignedUrl(path, 600);
  if (error) throw error;
  const extension = String(path).split(".").pop()?.toLowerCase() || "";
  const preview =
    extension === "pdf"
      ? `<iframe class="receipt-frame" src="${escapeHtml(data.signedUrl)}" title="Comprobante de pago"></iframe>`
      : `<img class="receipt-image" src="${escapeHtml(data.signedUrl)}" alt="Comprobante de pago" />`;
  const root = document.createElement("div");
  root.className = "modal-backdrop receipt-backdrop";
  root.id = "receipt-modal";
  root.innerHTML = `<section class="modal receipt-modal" role="dialog" aria-modal="true" aria-labelledby="receipt-title"><button class="modal-close" data-close-receipt aria-label="Cerrar">×</button><span class="modal-kicker">Inscripción · Comprobante</span><h2 id="receipt-title">Comprobante de pago</h2><div class="receipt-preview">${preview}</div><button class="button secondary full" data-close-receipt>Cerrar</button></section>`;
  document.body.append(root);
  const close = () => root.remove();
  root
    .querySelectorAll("[data-close-receipt]")
    .forEach((element) => element.addEventListener("click", close));
  root.addEventListener("click", (event) => {
    if (event.target === root) close();
  });
}

function showCreateModal() {
  const root = document.createElement("div");
  root.className = "modal-backdrop";
  root.id = "create-modal";
  root.innerHTML = `<section class="modal"><button class="modal-close" data-close>×</button><h2>Crear nuevo sorteo</h2><form id="create-raffle-form" class="form-grid"><label class="form-label full">Título<input class="field" name="title" maxlength="140" required /></label><label class="form-label full">Descripción<textarea class="field" name="description" maxlength="500"></textarea></label><label class="form-label full">Detalles<textarea class="field" name="details" maxlength="1200"></textarea></label><label class="form-label">Precio del ticket<input class="field" name="ticket_price" type="number" min="0.01" step="0.01" value="5" required /></label><label class="form-label">Fecha del sorteo<input class="field" name="draw_date" type="datetime-local" /></label><label class="form-label full">Imagen URL (opcional)<input class="field" name="image_url" type="url" placeholder="https://..." /></label><label class="form-label full">Premios, uno por línea<textarea class="field" name="prizes" placeholder="Laptop gamer\nMonitor\nAccesorios"></textarea></label><button class="button full" type="submit">Guardar sorteo</button></form></section>`;
  document.body.append(root);
  root
    .querySelector("[data-close]")
    .addEventListener("click", () => root.remove());
  root
    .querySelector("#create-raffle-form")
    .addEventListener("submit", createRaffle);
}

async function createRaffle(event) {
  event.preventDefault();
  const data = new FormData(event.currentTarget);
  const title = String(data.get("title") || "").trim();
  const prizeNames = String(data.get("prizes") || "")
    .split("\n")
    .map((value) => value.trim())
    .filter(Boolean);
  if (!title || !prizeNames.length)
    return toast("Agrega un título y al menos un premio.", "error");
  const button = event.currentTarget.querySelector("button");
  button.disabled = true;
  try {
    const raffleInsert = await supabase
      .from("raffles")
      .insert({
        title,
        description: String(data.get("description") || "").trim() || null,
        details: String(data.get("details") || "").trim() || null,
        ticket_price: Number(data.get("ticket_price")),
        draw_date: data.get("draw_date")
          ? new Date(String(data.get("draw_date"))).toISOString()
          : null,
        image_url: String(data.get("image_url") || "").trim() || null,
        status: "activo",
      })
      .select("id")
      .single();
    if (raffleInsert.error) throw raffleInsert.error;
    const prizesInsert = await supabase.from("prizes").insert(
      prizeNames.map((name, index) => ({
        raffle_id: raffleInsert.data.id,
        position: index + 1,
        name,
      })),
    );
    if (prizesInsert.error) throw prizesInsert.error;
    document.querySelector("#create-modal")?.remove();
    toast("Sorteo creado correctamente.", "success");
    await loadRaffles();
    renderDashboard();
  } catch (error) {
    button.disabled = false;
    toast(error.message, "error");
  }
}

async function signIn(event) {
  event.preventDefault();
  if (!supabase) return renderLogin("Configura Supabase en admin/config.js.");
  const data = new FormData(event.currentTarget);
  const { data: session, error } = await supabase.auth.signInWithPassword({
    email: String(data.get("email")),
    password: String(data.get("password")),
  });
  if (error) return renderLogin(error.message);
  try {
    const { data: isAdmin, error: roleError } = await supabase.rpc("has_role", {
      _user_id: session.user.id,
      _role: "admin",
    });
    if (roleError || !isAdmin) {
      await supabase.auth.signOut();
      return renderLogin("Este usuario no tiene el rol admin.");
    }
    state.user = session.user;
    await loadRaffles();
    await loadRegistrations();
    renderDashboard();
  } catch (error) {
    await supabase.auth.signOut();
    renderLogin(error.message);
  }
}
async function signOut() {
  await supabase.auth.signOut();
  state.user = null;
  renderLogin();
}
async function loadRaffles() {
  const { data, error } = await supabase
    .from("raffles")
    .select(
      "id,title,description,details,ticket_price,draw_date,status,image_url,prizes(id,position,name,winner_ticket_number,winner_name)",
    )
    .order("created_at", { ascending: false });
  if (error) throw error;
  state.raffles = (data || []).map((item) => ({
    ...item,
    ticket_price: Number(item.ticket_price),
    prizes: (item.prizes || []).sort((a, b) => a.position - b.position),
  }));
  if (
    !state.selectedRaffleId ||
    !state.raffles.some((item) => item.id === state.selectedRaffleId)
  )
    state.selectedRaffleId = state.raffles[0]?.id || "";
}
async function loadRegistrations() {
  if (!state.selectedRaffleId) {
    state.registrations = [];
    return;
  }
  const { data, error } = await supabase
    .from("registrations")
    .select(
      "id,raffle_id,dni,full_name,phone,email,quantity,amount,status,receipt_url,created_at,tickets(number)",
    )
    .eq("raffle_id", state.selectedRaffleId)
    .order("created_at", { ascending: false });
  if (error) throw error;
  state.registrations = (data || []).map((item) => ({
    ...item,
    tickets: (item.tickets || []).map((ticket) => ticket.number),
  }));
}

if (!supabase)
  renderLogin("No hay configuración de Supabase en admin/config.js.");
else
  supabase.auth.getSession().then(async ({ data }) => {
    if (!data.session) return renderLogin();
    state.user = data.session.user;
    try {
      const { data: isAdmin } = await supabase.rpc("has_role", {
        _user_id: state.user.id,
        _role: "admin",
      });
      if (!isAdmin) return renderLogin("Este usuario no tiene el rol admin.");
      await loadRaffles();
      await loadRegistrations();
      renderDashboard();
    } catch (error) {
      renderLogin(error.message);
    }
  });
