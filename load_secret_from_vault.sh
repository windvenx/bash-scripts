#!/bin/bash
set -e  # Выход при ошибке

export VAULT_ADDR="${VAULT_ADDR:-https://100.--.--.--:8200}"
export VAULT_TOKEN="${VAULT_TOKEN:-hvs.S8RHA------------------}"  

if [ -z "$VAULT_TOKEN" ]; then
  echo "❌ Error: VAULT_TOKEN not set"
  echo "Export it first: export VAULT_TOKEN=hvs.xxxxx"
  exit 1
fi

echo "🔐 Fetching secrets from Vault ($VAULT_ADDR)..."

# Function to merge fetched env with example template
merge_env() {
  local fetched_file="$1"
  local example_file="$2"
  local output_file="$3"

  if [ ! -f "$example_file" ]; then
    echo "❌ Error: Example file $example_file not found. Create it from the template."
    exit 1
  fi

  # Copy example to output
  cp "$example_file" "$output_file"

  # Parse fetched_file into associative array, handling multi-line values
  declare -A secrets
  current_key=""
  current_val=""
  while IFS= read -r line; do
    if [[ $line =~ ^([A-Z_0-9]+)= ]]; then
      if [[ -n "$current_key" ]]; then
        secrets["$current_key"]="$current_val"
      fi
      current_key="${BASH_REMATCH[1]}"
      current_val="${line#*=}"
    else
      current_val="$current_val"$'\n'"$line"
    fi
  done < "$fetched_file"
  if [[ -n "$current_key" ]]; then
    secrets["$current_key"]="$current_val"
  fi

  # For each secret, update in place or append
  for key in "${!secrets[@]}"; do
    val="${secrets[$key]}"

    # Trim leading/trailing whitespace (including newlines)
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"

    # If value contains spaces or #, quote it if not already quoted
    if [[ ! $val =~ ^\".*\"$ ]] && ([[ "$val" =~ [[:space:]] ]] || [[ "$val" =~ \# ]]); then
      val="\"$val\""
    fi

    temp_head=$(mktemp)
    temp_tail=$(mktemp)

    # Update if exists
    if grep -q "^${key}=" "$output_file"; then
      line_num=$(grep -n "^${key}=" "$output_file" | cut -d: -f1 | head -n1)
      head -n $((line_num - 1)) "$output_file" > "$temp_head"
      tail -n +$((line_num + 1)) "$output_file" > "$temp_tail"
      cat "$temp_head" > "$output_file"
      echo "${key}=${val}" >> "$output_file"
      cat "$temp_tail" >> "$output_file"
    else
      # Optional: Uncomment if commented version exists and no active
      if grep -q "^#${key}=" "$output_file" && ! grep -q "^${key}=" "$output_file"; then
        line_num=$(grep -n "^#${key}=" "$output_file" | cut -d: -f1 | head -n1)
        head -n $((line_num - 1)) "$output_file" > "$temp_head"
        tail -n +$((line_num + 1)) "$output_file" > "$temp_tail"
        cat "$temp_head" > "$output_file"
        echo "${key}=${val}" >> "$output_file"
        cat "$temp_tail" >> "$output_file"
      else
        # Append with newlines preserved
        echo "${key}=${val}" >> "$output_file"
      fi
    fi

    rm "$temp_head" "$temp_tail"
  done

  # Remove duplicate keys, keeping the first occurrence (handles multi-line values)
  awk '
  BEGIN { FS="="; OFS="=" }
  $1 ~ /^[A-Z_0-9]+$/ {
    if (!seen[$1]++) {
      print $0;
      nextline_is_cont=1;
    } else {
      nextline_is_cont=0;
      next;
    }
  }
  {
    if (nextline_is_cont || $1 !~ /^[A-Z_0-9]+$/) {
      print $0;
      if ($0 ~ /^[A-Z_0-9]+=/) nextline_is_cont=0;
    } else {
      nextline_is_cont=0;
    }
  }' "$output_file" > temp_env && mv temp_env "$output_file"
}

# Backend secrets
echo "  → Loading backend/env..."
temp_fetched=$(mktemp)
VAULT_SKIP_VERIFY=1 vault kv get -field=data -format=json cubbyhole/backend/env | \
  jq -r 'to_entries | .[] | "\(.key)=\(.value)"' > "$temp_fetched"

merge_env "$temp_fetched" "server/.env.example" "server/.env"
rm "$temp_fetched"

# Frontend secrets
echo "  → Loading frontend/env..."
temp_fetched=$(mktemp)
VAULT_SKIP_VERIFY=1 vault kv get -field=data -format=json cubbyhole/frontend/env | \
  jq -r 'to_entries | .[] | "\(.key)=\(..value)"' > "$temp_fetched"

merge_env "$temp_fetched" "client/.env.local.example" "client/.env.local"
rm "$temp_fetched"

echo "✅ Secrets loaded (merged with examples using pure bash, multi-line and duplicates handled):"
echo "   📁 server/.env ($(wc -l < server/.env) vars)"
echo "   📁 client/.env.local ($(wc -l < client/.env.local) vars)"
echo ""
echo "▶️  Run: docker-compose -f docker-compose-local.yml up"
