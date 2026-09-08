-- Cada premio se sortea una sola vez y muestra ticket y nombre del ganador.
BEGIN;

CREATE OR REPLACE FUNCTION public.sortear_ganador(p_prize_id uuid)
RETURNS TABLE (ticket_number integer, winner_name text, attempt_number integer, outcome text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_prize public.prizes%ROWTYPE;
  v_number integer;
  v_name text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;
  SELECT p.* INTO v_prize FROM public.prizes p WHERE p.id = p_prize_id FOR UPDATE;
  IF v_prize.id IS NULL THEN RAISE EXCEPTION 'El premio no existe'; END IF;
  IF v_prize.winner_ticket_number IS NOT NULL THEN RAISE EXCEPTION 'Este premio ya tiene ganador'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(v_prize.raffle_id::text, 0));
  SELECT t.number, r.full_name INTO v_number, v_name
  FROM public.tickets t JOIN public.registrations r ON r.id = t.registration_id
  WHERE t.raffle_id = v_prize.raffle_id AND r.status = 'aprobado'
    AND NOT EXISTS (SELECT 1 FROM public.draw_attempts a WHERE a.raffle_id = v_prize.raffle_id AND a.ticket_number = t.number)
  ORDER BY random() LIMIT 1;
  IF v_number IS NULL THEN RAISE EXCEPTION 'No hay tickets aprobados disponibles'; END IF;
  DELETE FROM public.draw_attempts WHERE prize_id = p_prize_id;
  INSERT INTO public.draw_attempts (raffle_id, prize_id, attempt_number, ticket_number, participant_name, outcome)
  VALUES (v_prize.raffle_id, p_prize_id, 1, v_number, v_name, 'ganador');
  UPDATE public.prizes SET winner_ticket_number = v_number, winner_name = v_name WHERE id = p_prize_id;
  RETURN QUERY SELECT v_number, v_name, 1, 'ganador'::text;
END;
$$;

REVOKE ALL ON FUNCTION public.sortear_ganador(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sortear_ganador(uuid) TO authenticated, service_role;

COMMIT;
