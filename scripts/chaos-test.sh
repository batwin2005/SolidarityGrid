#!/usr/bin/env bash
set -euo pipefail

WAIT_BEFORE_KILL=${1:-3}
WAIT_FOR_RECOVERY=${2:-12}

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GRAY='\033[0;37m'
DARK_GRAY='\033[1;30m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║      SolidarityGrid — Chaos Engineering Test     ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo ""

NODES=("http://localhost:5001" "http://localhost:5002" "http://localhost:5003")
NAMES=("NodeA" "NodeB" "NodeC")
IDX=$((RANDOM % 3))
TARGET_URL="${NODES[$IDX]}"
TARGET_NAME="${NAMES[$IDX]}"

echo -e "➤ Sending payment to ${TARGET_NAME} (${TARGET_URL})..."
echo ""

RESPONSE=$(curl -s -X POST "${TARGET_URL}/pay" \
  -H "Content-Type: application/json" \
  -d '{"amount": 99.95, "currency": "USD"}')

TX_ID=$(echo "$RESPONSE" | grep -o '"transactionId":"[^"]*"' | cut -d'"' -f4)

if [ -z "$TX_ID" ]; then
  echo -e "  ${RED}✗ Failed to send payment${NC}"
  echo "$RESPONSE"
  exit 1
fi

PROCESSING_NODE=$(echo "$RESPONSE" | grep -o '"node":"[^"]*"' | cut -d'"' -f4)

echo -e "  ${YELLOW}✔ Transaction $TX_ID created${NC}"
echo -e "  ✔ Assigned to ${PROCESSING_NODE}"
echo -e "  ✔ Estimated processing: $(echo $RESPONSE | grep -o '"estimatedDelayMs":[0-9]*' | cut -d: -f2)ms"
echo ""

echo -e "➤ Waiting ${WAIT_BEFORE_KILL} seconds before injecting fault..."
sleep "$WAIT_BEFORE_KILL"

CONTAINER_NAME="solidaritygrid-node-$(echo "$PROCESSING_NODE" | tr '[:upper:]' '[:lower:]')"

echo ""
echo -e "  ${RED}⚡ KILLING ${PROCESSING_NODE} container...${NC}"
docker stop "$CONTAINER_NAME" 2>/dev/null || docker kill "$CONTAINER_NAME" 2>/dev/null
echo -e "  ${RED}✔ ${PROCESSING_NODE} stopped${NC}"
echo ""

echo -e "➤ Waiting ${WAIT_FOR_RECOVERY} seconds for cluster to self-heal..."
sleep "$WAIT_FOR_RECOVERY"

echo ""
echo -e "${CYAN}➤ Checking transaction status across surviving nodes...${NC}"
echo ""

FOUND=false

for i in "${!NODES[@]}"; do
  if [ "${NAMES[$i]}" = "${PROCESSING_NODE}" ]; then continue; fi

  URL="${NODES[$i]}"
  NAME="${NAMES[$i]}"

  TXNS=$(curl -s "${URL}/transactions")
  STATE=$(echo "$TXNS" | grep -o '"id":"'"${TX_ID}"'","[^}]*state":"[^"]*"' | grep -o '"state":"[^"]*"' | cut -d'"' -f4)
  OWNER=$(echo "$TXNS" | grep -o '"id":"'"${TX_ID}"'","[^}]*ownerNodeId":"[^"]*"' | grep -o '"ownerNodeId":"[^"]*"' | cut -d'"' -f4)

  if [ -n "$STATE" ]; then
    FOUND=true
    case "$STATE" in
      "Completed")  COLOR=$GREEN   SYMBOL="✔" ;;
      "Processing") COLOR=$YELLOW  SYMBOL="⏳" ;;
      "Failed")     COLOR=$RED     SYMBOL="✗" ;;
      *)            COLOR=$GRAY    SYMBOL="?" ;;
    esac
    echo -e "  ${COLOR}${SYMBOL} ${NAME}: ${STATE} (owner: ${OWNER})${NC}"
  else
    echo -e "  ${DARK_GRAY}- ${NAME}: transaction not found in local state${NC}"
  fi
done

echo ""

if [ "$FOUND" = true ]; then
  echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║           CHAOS TEST PASSED ✓                    ║${NC}"
  echo -e "${GREEN}║  The cluster detected the failure and recovered  ║${NC}"
  echo -e "${GREEN}║  the orphaned transaction automatically.         ║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
else
  echo -e "${RED}╔══════════════════════════════════════════════════╗${NC}"
  echo -e "${RED}║           CHAOS TEST FAILED ✗                    ║${NC}"
  echo -e "${RED}║  No surviving node has the transaction.          ║${NC}"
  echo -e "${RED}╚══════════════════════════════════════════════════╝${NC}"
fi

echo ""
echo -e "➤ Restarting ${PROCESSING_NODE} for future tests..."
docker start "$CONTAINER_NAME" 2>/dev/null && echo -e "  ${GREEN}✔ ${PROCESSING_NODE} restarted${NC}" || echo -e "  ${YELLOW}⚠ Could not restart ${PROCESSING_NODE}${NC}"
echo ""
