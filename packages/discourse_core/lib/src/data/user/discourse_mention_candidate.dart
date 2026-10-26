/// Someone (or a group) an `@` in a composer can name: what
/// `/u/search/users` returns for the web's mention autocomplete.
/// [username] is what goes after the `@`; [name] is a person's full name or
/// a group's full_name, when it has one.
typedef DiscourseMentionCandidate = ({
  String username,
  String? name,
  String? avatarUrl,
  bool isGroup,
});
