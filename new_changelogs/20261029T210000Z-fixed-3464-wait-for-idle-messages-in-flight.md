- **`wait_for_idle()` no longer returns with messages in flight between
  cores.** The count of messages still pending read each core's sent and
  handled counts in turn, so a message sent on a core already read and
  handled on one read after cancelled the reply it sent, which was still
  pending: two actors trading messages on two cores (a stream's chunks and
  credits) could make the wait return mid-exchange. Every core's handled
  count is now read before every core's sent count, and a batch of sends is
  counted before its receiver can take it, as a single send always was
  (#3464).
