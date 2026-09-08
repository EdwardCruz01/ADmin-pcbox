-- Mantiene dos sorteos: el anterior histórico/inactivo y el nuevo activo a S/ 1.

BEGIN;

UPDATE public.raffles SET ticket_price = 1 WHERE title = 'Sorteo PC BOX - Próximamente';

DO $$
DECLARE v_raffle uuid;
BEGIN
  SELECT id INTO v_raffle FROM public.raffles WHERE title = '1° Gran Sorteo del Shucuy Regalon' LIMIT 1;
  IF v_raffle IS NULL THEN
    INSERT INTO public.raffles (title, description, details, image_url, ticket_price, status, draw_date)
    VALUES ('1° Gran Sorteo del Shucuy Regalon', 'El próximo PC profesional puede ser tuyo junto a cinco premios tecnológicos.', 'Sorteo histórico. La participación se encuentra cerrada.', 'assets/flyer-tarjeta-pa-salado.png', 5, 'inactivo', '2026-09-23 23:59:59-05:00')
    RETURNING id INTO v_raffle;
  ELSE
    UPDATE public.raffles SET status = 'inactivo', ticket_price = 5 WHERE id = v_raffle;
  END IF;
  INSERT INTO public.prizes (raffle_id, position, name, image_url)
  SELECT v_raffle, p.position, p.name, p.image_url
  FROM (VALUES
    (1, 'PC Gamer profesional + silla gaming + mesa elevable', 'assets/premio-mayor-setup-antryx.png'),
    (2, 'Impresora Epson L3310', 'assets/premio-impresora-epson-l3310.png'),
    (3, 'Tablet Samsung Tab A11', 'assets/premio-tablet-samsung-tab-a11.png'),
    (4, 'Audífono profesional Logitech G635', 'assets/premio-audifono-logitech-g635.png'),
    (5, 'Teclado gamer mecánico Antryx Zigra Evo', 'assets/premio-teclado-antryx-zigra-evo.png'),
    (6, 'Parlante Halion Fiesta HA-R63', 'assets/premio-parlante-hal-fiesta-ha-r63.png')
  ) AS p(position, name, image_url)
  WHERE NOT EXISTS (SELECT 1 FROM public.prizes existing WHERE existing.raffle_id = v_raffle AND existing.position = p.position);
END;
$$;

COMMIT;
