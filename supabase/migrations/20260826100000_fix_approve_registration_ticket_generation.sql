-- Corrige la aprobación de inscripciones y la asignación consecutiva de tickets.
-- Se califican todas las columnas para evitar la ambigüedad con el campo
-- registration_id declarado por RETURNS TABLE.
-- También se vuelve a comprobar la inscripción después del bloqueo por sorteo
-- para evitar tickets duplicados si dos administradores aprueban a la vez.

CREATE OR REPLACE FUNCTION public.aprobar_inscripcion(
  p_registration_id uuid,
  p_nota text DEFAULT NULL
)
RETURNS TABLE (registration_id uuid, numbers int[])
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reg public.registrations%ROWTYPE;
  v_next int;
  v_nums int[];
  v_existing_numbers int[];
  i int;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  SELECT r.*
  INTO v_reg
  FROM public.registrations AS r
  WHERE r.id = p_registration_id
  FOR UPDATE;

  IF v_reg.id IS NULL THEN
    RAISE EXCEPTION 'La inscripción no existe';
  END IF;

  IF v_reg.status = 'rechazado' THEN
    RAISE EXCEPTION 'No se puede aprobar una inscripción rechazada';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_reg.raffle_id::text, 0));

  -- Se consulta después del bloqueo para que la operación sea idempotente.
  SELECT array_agg(t.number ORDER BY t.number)
  INTO v_existing_numbers
  FROM public.tickets AS t
  WHERE t.registration_id = p_registration_id;

  IF v_existing_numbers IS NOT NULL THEN
    RETURN QUERY SELECT p_registration_id, v_existing_numbers;
    RETURN;
  END IF;

  SELECT COALESCE(MAX(t.number) + 1, 100)
  INTO v_next
  FROM public.tickets AS t
  WHERE t.raffle_id = v_reg.raffle_id;

  v_nums := ARRAY[]::int[];

  FOR i IN 0 .. (v_reg.quantity - 1) LOOP
    INSERT INTO public.tickets (raffle_id, registration_id, number)
    VALUES (v_reg.raffle_id, v_reg.id, v_next + i);
    v_nums := array_append(v_nums, v_next + i);
  END LOOP;

  UPDATE public.registrations AS r
  SET status = 'aprobado',
      admin_note = COALESCE(p_nota, r.admin_note),
      reviewed_at = now()
  WHERE r.id = p_registration_id;

  RETURN QUERY SELECT p_registration_id, v_nums;
END;
$$;

REVOKE ALL ON FUNCTION public.aprobar_inscripcion(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.aprobar_inscripcion(uuid, text) TO authenticated, service_role;
