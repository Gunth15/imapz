//Every mailbox has two 32-bit integers associated with them to aid in UID handlng
//1. UIDNEXT: next unique identifier
//2. UIDVALIDITY(should not change unless a mailbox is delted/changed or ther is no mechanism on the server to store UIDs)
//UIDVALIDITY sent at mailbox selection time
name: []const u8,
UIDNEXT: u32,
UIDVALIDITY: u32,

//Mailbox name are [NET-UNICODE] MUST interpret any 8-bit mailbox names returned
//by LIST as [NET-UNICIDE].
//Server MAY accept denormalized UTF-8 mailbox name and convert it to Unicode Normalization Form C (NFC) (as per Net-Unicode requirements) prior to creation
//NOTE: UTF-8 should be converted to NFC to be considered NET-UNICODE for max portability
//
//INBOX is a special mailbox name(the primary mailbox) MAY not exist on some servers
//Case sensativity is implementation dependant
//
//   1.  Any character that is one of the atom-specials (see "Formal
//   Syntax" in Section 9) will require that the mailbox name be
//   represented as a quoted string or literal.
//
//   2.  CTL and other non-graphic characters are difficult to represent
//   in a user interface and are best avoided.  Servers MAY refuse to
//   create mailbox names containing Unicode CTL characters.
//   3.  Although the list-wildcard characters ("%" and "*") are valid in
//   a mailbox name, it is difficult to use such mailbox names with
//   the LIST command due to the conflict with wildcard
//   interpretation
//   4.  Usually, a character (determined by the server implementation) is
//   reserved to delimit levels of hierarchy.
//   5.  Two characters, "#" and "&", have meanings by convention and
//   should be avoided except when used in that convention.  See
//   Section 5.1.2.1 and Appendix A.1, respectively.
