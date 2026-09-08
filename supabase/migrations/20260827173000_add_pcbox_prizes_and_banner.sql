-- Premios y banner oficiales del sorteo PC BOX.
BEGIN;
UPDATE public.raffles
SET image_url = 'assets/banner-sorteo-pcbox.png',
    description = 'Participa y gana productos PC BOX seleccionados.',
    details = 'Sorteo PC BOX con cuatro premios. Cada ticket cuesta S/ 1 y la inscripción se valida mediante comprobante de Yape.'
WHERE title = 'Sorteo PC BOX - Próximamente';

DO $$
DECLARE v_raffle uuid;
BEGIN
  SELECT id INTO v_raffle FROM public.raffles WHERE title = 'Sorteo PC BOX - Próximamente' LIMIT 1;
  IF v_raffle IS NULL THEN RAISE EXCEPTION 'No se encontró el sorteo PC BOX activo'; END IF;
  INSERT INTO public.prizes (raffle_id, position, name, image_url)
  SELECT v_raffle, p.position, p.name, p.image_url
  FROM (VALUES
    (1, 'Calculadora Deltron CALC2807 con anotador integrado', 'assets/premio-pcbox-calculadora.png'),
    (2, 'Polo Canon blanco', 'assets/premio-pcbox-polo-canon.png'),
    (3, 'Tomacorriente inteligente Teros TE-9102W', 'assets/premio-pcbox-tomacorriente.png'),
    (4, 'Vaso térmico Canon', 'assets/premio-pcbox-vaso-canon.png')
  ) AS p(position, name, image_url)
  WHERE NOT EXISTS (SELECT 1 FROM public.prizes existing WHERE existing.raffle_id = v_raffle AND existing.position = p.position);
END;
$$;
COMMIT;
