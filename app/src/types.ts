// Espelho das visões montadas pelo backend (TrucoOn.Truco.Rooms.view/2 e Game.view/2).
export type Player = { id: string; name: string };

export type Seat = { seat: number; team: "a" | "b"; player: Player | null };

export type TrucoEvent = { type: string; version?: number; [k: string]: any };

export type Round = {
  number: number;
  status: "playing" | "truco_pending" | "mao_de_11" | "mao_de_ferro";
  category: string;
  current_bet: number;
  bet_pending_team: "a" | "b" | null;
  last_caller_team: "a" | "b" | null;
  current_turn: string | null;
  my_cards: string[];
  partner_cards: string[] | null;
  cards_left: Record<string, number>;
  plays_in_trick: { player_id: string; card: string }[];
  trick_results: ("a" | "b" | "draw")[];
};

export type GameView = {
  mode: "1v1" | "2v2";
  status: "playing" | "finished";
  scores: { a: number; b: number };
  winner_team: "a" | "b" | null;
  finish_reason: string | null;
  players: { id: string; name: string; team: "a" | "b"; seat: number }[];
  last_trick: { number: number; winner_team: string | null; plays: { player_id: string; card: string }[] } | null;
  last_round: { number: number; winner_team: string | null; tentos: number; reason: string } | null;
  round: Round | null;
};

export type RoomView = {
  code: string;
  mode: "1v1" | "2v2";
  status: "lobby" | "playing" | "finished";
  host_id: string;
  capacity: number;
  members: Player[];
  seats: Seat[];
  version: number;
  me: { id: string; seat: number | null; team: "a" | "b" | null };
  is_host: boolean;
  game: GameView | null;
  events: TrucoEvent[];
};

export type PeerInfo = {
  peer_id: number | null;
  region: string | null;
  ordering: string;
  group_ready: boolean;
  sequencer: number | false;
  peers: { id: number; region: string; url: string }[];
};
