// Motivos de erro do backend → texto para o jogador.
const REASONS: Record<string, string> = {
  not_your_turn: "Não é sua vez",
  truco_pending: "Responda o truco primeiro",
  card_not_in_hand: "Essa carta não está na sua mão",
  seat_taken: "Cadeira ocupada",
  seats_not_filled: "Faltam jogadores sentados",
  not_host: "Só o anfitrião pode fazer isso",
  room_full: "Mesa cheia",
  room_not_found: "Mesa não encontrada",
  game_in_progress: "Partida em andamento",
  same_team_cannot_raise: "Seu time já pediu",
  bet_already_pending: "Já tem um pedido pendente",
  max_bet_reached: "Já está valendo 12",
  truco_disabled_in_special_round: "Não vale truco nesta mão",
  not_pending_team: "Não é seu time que responde",
  no_bet_pending: "Nada para responder",
  mao_de_11_pending: "Decidam a mão de 11 primeiro",
  not_mao_de_11_team: "Só o time com 11 decide",
  timeout: "O servidor demorou para responder",
  game_finished: "A partida acabou",
};

export const reasonText = (r: string) => REASONS[r] ?? r;

export function describeEvent(e: any, name: (id: string) => string): string | null {
  switch (e.type) {
    case "room_created": return "Mesa criada";
    case "player_joined": return `${e.name} entrou`;
    case "player_left": return `${name(e.player_id)} saiu`;
    case "seat_taken": return `${name(e.player_id)} sentou (time ${e.team.toUpperCase()})`;
    case "game_started": return "Partida começou!";
    case "round_started": return `Mão ${e.number}${e.category !== "normal" ? ` (${e.category.replace(/_/g, " ")})` : ""}`;
    case "card_played": return null;
    case "trick_finished": return e.winner_team ? `Vaza para ${name(e.winner_player_id)}` : "Vaza empatada (cangou)";
    case "truco_called": return `${name(e.player_id)} pediu TRUCO!`;
    case "truco_raised": return `${name(e.player_id)} pediu ${e.current_bet}!`;
    case "truco_accepted": return `${name(e.player_id)} aceitou (vale ${e.current_bet})`;
    case "truco_rejected": return `${name(e.player_id)} fugiu`;
    case "mao_de_11_accepted": return `${name(e.player_id)} topou a mão de 11`;
    case "mao_de_11_rejected": return `${name(e.player_id)} correu da mão de 11`;
    case "round_finished": return e.winner_team ? `Time ${e.winner_team.toUpperCase()} leva ${e.tentos}` : "Mão empatada";
    case "game_over": return `Fim de jogo: time ${e.winner_team.toUpperCase()} venceu`;
    default: return null;
  }
}
