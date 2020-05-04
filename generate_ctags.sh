#!/bin/bash

IS_GIT=$(git rev-parse --git-dir > /dev/null 2>&1;)

if [[ "$IS_GIT" -ne 0 ]]; then
  echo "Cannot generate ctags, $(pwd) not a git-repository"
  exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
CTAGS_CACHE="$HOME/.ctags_cache"
SUPPORTED_FILES_REGEX="(.*\.py|.*\.m|.*\.c|.*\.h|.*\.swift)$"
REPO_CACHE="$CTAGS_CACHE/$REPO_ROOT/"
LAST_RUN_HASH_FILE="$REPO_CACHE/.tags_last_run_hash"
SQLITE_DB="$REPO_CACHE/tags.sqlite"

if [ ! -d "$REPO_CACHE" ]; then
  mkdir -p "$REPO_CACHE"
fi

print_progress() {
  number_of_bars=40
  done=$((number_of_bars * $1 / 100))
  left=$((number_of_bars - done ))
  done_str=$(printf "%${done}s")
  empty_str=$(printf "%${left}s")
  printf "\rProgress: [${done_str// /X}${empty_str// /-}] %d%%" "$1"
}

create_sqlite_db() {
  sqlite3 "$SQLITE_DB" "CREATE TABLE \"TAGS\" (\"directory\"	TEXT, \"name\"	TEXT, \"filename\"	TEXT, \"cmd\"	TEXT, \"kind\"	TEXT );"
  sqlite3 "$SQLITE_DB" "CREATE INDEX \"TAGS_INDEX\" ON \"TAGS\" ( \"directory\"	ASC, \"name\"	ASC, \"filename\"	ASC );"
}

insert_in_sqlite_db() {
   directory=$1
   #echo "$directory"
   sqlite3 "$SQLITE_DB" "DELETE FROM \"TAGS\" where directory == \"$directory\""
   grep -v "\!_TAG_" < /dev/stdin | awk -v directory="$directory" '{
   name = $1
   gsub("\"", "\"\"", name)
   filename = $2
   gsub("\"", "\"\"", filename)
   command = substr($0, index($0, "/^"), index($0, ";\"") - index($0, "/^") + 2)
   gsub("\"", "\"\"", command)
   type = substr($0, index($0, ";\"") + 5, 1)
   gsub("\"", "\"\"", type)
   query = "INSERT INTO \"TAGS\"( \"directory\",\"name\",\"filename\",\"cmd\",\"kind\") VALUES (\"%s\",\"%s\",\"%s\",\"%s\",\"%s\");\n"
   printf (query, directory, name, filename, command, type ) }' | tee -a "/tmp/sqlite_insert.log" |  sqlite3 "$SQLITE_DB"
}


generate_tags() {
  SECONDS=0
  all_directories=$(mktemp -t process_dirs)
  cat /dev/stdin > "$all_directories"
  total_dirs=$(wc -l < "$all_directories")
  number_of_runs=0
  while read -r dir_path
  do
    tag_file="$REPO_CACHE/$dir_path/tags"
    rm -f "$tag_file"
    IFS=$'\n' read -r -d ' ' -a files < <(git ls-tree HEAD -- "$dir_path/" | grep "blob" | grep -E "$SUPPORTED_FILES_REGEX" | awk '{print $4 }')
    if [ "${#files[@]}" -gt 0 ]; then
      [ "$( jobs | wc -l )" -ge "$( nproc )" ] && wait
      ctags -f - "${files[@]}" | insert_in_sqlite_db "$dir_path"
    fi
    number_of_runs=$(( number_of_runs + 1 ))
    progress=$(( number_of_runs * 100 / total_dirs ))
    print_progress "$progress"
  done < "$all_directories"
  printf "\n"
  echo "$((SECONDS / 60)) minutes and $((SECONDS % 60)) seconds elapsed."

}

if [ -f "$LAST_RUN_HASH_FILE" ]; then
  read -r LAST_RUN_HASH < "$LAST_RUN_HASH_FILE"
  git diff "$LAST_RUN_HASH" --name-only | grep -E "$SUPPORTED_FILES_REGEX" | xargs -L 1 dirname |  sort | uniq | generate_tags
else
  echo "No previous run found. Generating tags from scratch"
  create_sqlite_db
  git ls-tree -rt HEAD:./ | awk '{if ($2 == "tree") print $4;}' | generate_tags
fi

# shellcheck disable=SC2181
if [ $? -eq 0 ]; then
  git rev-parse HEAD > "$LAST_RUN_HASH_FILE"
  echo "Done"
fi
