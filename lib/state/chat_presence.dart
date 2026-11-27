/// Tracks which conversation is currently open so the chat list does not play
/// duplicate sounds for messages already handled by the chat room.
class ChatPresence {
  static int? activeConversationId;
}
