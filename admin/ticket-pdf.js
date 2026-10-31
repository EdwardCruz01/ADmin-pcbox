let pdfLibPromise;

function loadPdfLib() {
  if (window.PDFLib) return Promise.resolve(window.PDFLib);
  if (!pdfLibPromise) {
    pdfLibPromise = new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.src = new URL("./vendor/pdf-lib.min.js", import.meta.url).href;
      script.onload = () =>
        window.PDFLib ? resolve(window.PDFLib) : reject(new Error("No se pudo abrir el generador de PDF."));
      script.onerror = () => reject(new Error("No se pudo cargar el generador de PDF."));
      document.head.append(script);
    }).catch((error) => {
      pdfLibPromise = null;
      throw error;
    });
  }
  return pdfLibPromise;
}

function pdfText(font, value) {
  return Array.from(String(value ?? "-")).map((character) => {
    try {
      font.encodeText(character);
      return character;
    } catch {
      const latin = character.normalize("NFKD").replace(/[\u0300-\u036f]/g, "");
      try {
        font.encodeText(latin);
        return latin;
      } catch {
        return "?";
      }
    }
  }).join("");
}

function fitText(font, value, maxWidth, preferredSize, minSize = 8) {
  const text = pdfText(font, value);
  let size = preferredSize;
  while (size > minSize && font.widthOfTextAtSize(text, size) > maxWidth) size -= 0.5;
  if (font.widthOfTextAtSize(text, size) <= maxWidth) return { text, size };
  let shortened = text;
  while (shortened && font.widthOfTextAtSize(`${shortened}…`, size) > maxWidth)
    shortened = shortened.slice(0, -1);
  return { text: `${shortened}…`, size };
}

function drawFitted(page, font, value, x, y, maxWidth, preferredSize, color) {
  const fitted = fitText(font, value, maxWidth, preferredSize);
  page.drawText(fitted.text, { x, y, size: fitted.size, font, color });
}

function cardBackground() {
  const canvas = document.createElement("canvas");
  canvas.width = 1046;
  canvas.height = 368;
  const context = canvas.getContext("2d");
  context.beginPath();
  context.roundRect(2, 2, 1042, 364, 38);
  context.clip();
  const gradient = context.createLinearGradient(0, 0, 1046, 368);
  gradient.addColorStop(0, "#720e9e");
  gradient.addColorStop(0.55, "#581477");
  gradient.addColorStop(1, "#321047");
  context.fillStyle = gradient;
  context.fillRect(0, 0, 1046, 368);
  const glow = context.createRadialGradient(120, 10, 0, 120, 10, 440);
  glow.addColorStop(0, "rgba(206,122,255,0.34)");
  glow.addColorStop(1, "rgba(206,122,255,0)");
  context.fillStyle = glow;
  context.fillRect(0, 0, 1046, 368);
  context.strokeStyle = "rgba(196,137,255,0.7)";
  context.lineWidth = 3;
  context.stroke();
  return canvas.toDataURL("image/png");
}

function fileSlug(value) {
  return String(value || "evento")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .slice(0, 50) || "evento";
}

export async function downloadTicketsPdf(raffle, tickets) {
  if (!raffle || !tickets.length) throw new Error("No hay tickets aprobados para descargar.");
  const { PDFDocument, StandardFonts, rgb } = await loadPdfLib();
  const pdf = await PDFDocument.create();
  pdf.setTitle(`Tickets aprobados - ${raffle.title}`);
  pdf.setAuthor("PC BOX Admin");
  const regular = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const background = await pdf.embedPng(cardBackground());
  const paper = [595.28, 841.89];
  const white = rgb(1, 1, 1);
  const muted = rgb(0.82, 0.76, 0.9);
  const green = rgb(0.79, 1, 0.85);
  const cardX = 36;
  const cardWidth = paper[0] - 72;
  const cardHeight = 184;
  const perPage = 3;
  const pageCount = Math.ceil(tickets.length / perPage);
  const generated = new Date().toLocaleDateString("es-PE", { dateStyle: "medium" });

  tickets.forEach(({ item, ticket }, index) => {
    const pageNumber = Math.floor(index / perPage);
    const slot = index % perPage;
    const page = slot === 0 ? pdf.addPage(paper) : pdf.getPage(pageNumber);
    if (slot === 0) {
      page.drawText("PC BOX  /  TICKETS APROBADOS", {
        x: 36, y: 806, size: 11, font: bold, color: rgb(0.3, 0.12, 0.49),
      });
      drawFitted(page, bold, raffle.title, 36, 782, 420, 14, rgb(0.09, 0.08, 0.16));
      page.drawText(`${tickets.length} tickets  |  ${pdfText(regular, generated)}`, {
        x: 36, y: 764, size: 9, font: regular, color: rgb(0.4, 0.4, 0.47),
      });
      page.drawText(`Página ${pageNumber + 1} de ${pageCount}`, {
        x: 36, y: 28, size: 9, font: regular, color: rgb(0.45, 0.45, 0.52),
      });
    }

    const top = 745 - slot * 203;
    const bottom = top - cardHeight;
    page.drawImage(background, { x: cardX, y: bottom, width: cardWidth, height: cardHeight });
    const left = cardX + 20;
    const right = cardX + 285;
    page.drawText("TICKET ASIGNADO", { x: left, y: top - 23, size: 8, font: bold, color: muted });
    drawFitted(page, bold, `#${ticket}`, left, top - 59, 290, 32, white);
    page.drawRectangle({ x: cardX + cardWidth - 89, y: top - 40, width: 69, height: 22, color: rgb(0.2, 0.34, 0.32), opacity: 0.75 });
    page.drawText("APROBADO", { x: cardX + cardWidth - 81, y: top - 33, size: 8, font: bold, color: green });
    page.drawLine({ start: { x: left, y: top - 72 }, end: { x: cardX + cardWidth - 20, y: top - 72 }, thickness: 0.7, color: white, opacity: 0.25 });

    const fields = [
      ["PARTICIPANTE", item.full_name, left, top - 90, 245],
      [item.document_type === "CE" ? "CARNET DE EXTRANJERÍA" : "DNI", item.dni, right, top - 90, 205],
      ["CELULAR", item.phone || "-", left, top - 127, 245],
      ["MONTO REGISTRADO", `S/ ${Number(item.amount || 0).toFixed(2)}`, right, top - 127, 205],
    ];
    fields.forEach(([label, value, x, y, width]) => {
      page.drawText(label, { x, y, size: 7, font: bold, color: muted });
      drawFitted(page, bold, value, x, y - 16, width, 11, white);
    });
    page.drawLine({ start: { x: left, y: top - 160 }, end: { x: cardX + cardWidth - 20, y: top - 160 }, thickness: 0.7, color: white, opacity: 0.25 });
    drawFitted(page, regular, `Registrado el ${new Date(item.created_at).toLocaleDateString("es-PE", { dateStyle: "medium" })}`, left, top - 176, cardWidth - 40, 8, muted);
  });

  const bytes = await pdf.save();
  const blob = new Blob([bytes], { type: "application/pdf" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `tickets-${fileSlug(raffle.title)}-${new Date().toISOString().slice(0, 10)}.pdf`;
  document.body.append(link);
  link.click();
  link.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 60000);
}
