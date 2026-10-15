/// The lifecycle states shown in the Downloads UI. These mirror libtorrent's
/// states plus two application-level ones (`resolvingMetadata`, `unavailable`).
enum TorrentTaskState {
  queued,
  resolvingMetadata,
  downloading,
  seeding,
  paused,
  completed,
  checking,
  failed,
  unavailable;

  bool get isActive =>
      this == downloading || this == seeding || this == resolvingMetadata || this == checking;
  bool get isTerminal => this == completed || this == failed || this == unavailable;
}

/// Explicit, testable state machine. Anything not listed is rejected, which
/// prevents the UI from showing e.g. "seeding" for a task that never started.
class TorrentStateMachine {
  static const Map<TorrentTaskState, Set<TorrentTaskState>> _transitions = {
    TorrentTaskState.queued: {
      TorrentTaskState.resolvingMetadata,
      TorrentTaskState.downloading,
      TorrentTaskState.paused,
      TorrentTaskState.failed,
      TorrentTaskState.checking,
    },
    TorrentTaskState.resolvingMetadata: {
      TorrentTaskState.downloading,
      TorrentTaskState.checking,
      TorrentTaskState.paused,
      TorrentTaskState.failed,
      TorrentTaskState.unavailable,
    },
    TorrentTaskState.downloading: {
      TorrentTaskState.seeding,
      TorrentTaskState.paused,
      TorrentTaskState.completed,
      TorrentTaskState.checking,
      TorrentTaskState.failed,
      TorrentTaskState.unavailable,
    },
    TorrentTaskState.seeding: {
      TorrentTaskState.paused,
      TorrentTaskState.completed,
      TorrentTaskState.failed,
      TorrentTaskState.unavailable,
    },
    TorrentTaskState.paused: {
      TorrentTaskState.queued,
      TorrentTaskState.downloading,
      TorrentTaskState.checking,
      TorrentTaskState.failed,
      TorrentTaskState.unavailable,
      TorrentTaskState.resolvingMetadata,
    },
    TorrentTaskState.checking: {
      TorrentTaskState.downloading,
      TorrentTaskState.seeding,
      TorrentTaskState.completed,
      TorrentTaskState.paused,
      TorrentTaskState.failed,
      TorrentTaskState.queued,
    },
    TorrentTaskState.completed: {
      TorrentTaskState.checking,
      TorrentTaskState.seeding,
      TorrentTaskState.queued,
      TorrentTaskState.paused,
      TorrentTaskState.failed,
    },
    TorrentTaskState.failed: {
      TorrentTaskState.queued,
      TorrentTaskState.resolvingMetadata,
      TorrentTaskState.checking,
      TorrentTaskState.paused,
    },
    TorrentTaskState.unavailable: {
      TorrentTaskState.queued,
      TorrentTaskState.resolvingMetadata,
      TorrentTaskState.checking,
      TorrentTaskState.paused,
    },
  };

  static bool canTransition(TorrentTaskState from, TorrentTaskState to) {
    if (from == to) return true;
    return _transitions[from]?.contains(to) ?? false;
  }

  /// Returns the next state, or throws when the transition is not permitted.
  static TorrentTaskState transition(TorrentTaskState from, TorrentTaskState to) {
    if (!canTransition(from, to)) {
      throw StateError('illegal torrent transition $from -> $to');
    }
    return to;
  }
}
