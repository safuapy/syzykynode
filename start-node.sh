#!/bin/bash

# Configuration
DATA_DIR="node1"
NETWORK_ID=736
P2P_PORT=30303
RPC_PORT=8545
WS_PORT=8546
LOG_FILE="node.log"

# Get external IP address
EXTERNAL_IP=$(curl -s https://api.ipify.org)
if [ -z "$EXTERNAL_IP" ]; then
    echo "Error: Could not determine external IP address"
    exit 1
fi

# Function to get enode URL
get_enode() {
    local admin_file=$(mktemp)
    echo 'admin.nodeInfo.enode' > "$admin_file"
    
    # Wait for node to start and get enode (timeout after 30 seconds)
    for i in {1..30}; do
        if geth attach --datadir $DATA_DIR --exec 'admin.nodeInfo.enode' 2>/dev/null; then
            break
        fi
        sleep 1
    done
    
    rm "$admin_file"
}

# Create data directory if it doesn't exist
mkdir -p $DATA_DIR

# Initialize the genesis block (only if not already initialized)
if [ ! -d "$DATA_DIR/geth" ]; then
    echo "Initializing genesis block..."
    geth init --datadir $DATA_DIR genesis.json
fi

# Import the private key and get the address (only if no accounts exist)
if [ ! -d "$DATA_DIR/keystore" ] || [ -z "$(ls -A $DATA_DIR/keystore)" ]; then
    echo "Importing private key..."
    if [ ! -f "private_key.txt" ]; then
        echo "Error: private_key.txt not found"
        exit 1
    fi
    geth account import --datadir $DATA_DIR private_key.txt
fi

# Get the account address
ACCOUNT_ADDRESS=$(geth account list --datadir $DATA_DIR | head -n 1 | cut -d '{' -f 2 | cut -d '}' -f 1)
if [ -z "$ACCOUNT_ADDRESS" ]; then
    echo "Error: Could not get account address"
    exit 1
fi
echo "Using account: 0x${ACCOUNT_ADDRESS}"

# Create a password file for unlocking the account
echo "" > $DATA_DIR/password.txt

# Start the node in the background
nohup geth \
  --datadir $DATA_DIR \
  --networkid $NETWORK_ID \
  --port $P2P_PORT \
  --nat extip:${EXTERNAL_IP} \
  --http \
  --http.addr "0.0.0.0" \
  --http.port $RPC_PORT \
  --http.corsdomain "*" \
  --http.api "eth,net,web3" \
  --http.vhosts "*" \
  --ws \
  --ws.addr "0.0.0.0" \
  --ws.port $WS_PORT \
  --ws.origins "*" \
  --ws.api "eth,net,web3" \
  --mine \
  --miner.etherbase "0x${ACCOUNT_ADDRESS}" \
  --unlock "0x${ACCOUNT_ADDRESS}" \
  --password $DATA_DIR/password.txt \
  --allow-insecure-unlock \
  --syncmode "full" \
  --metrics \
  --pprof \
  --verbosity 3 \
  --txpool.accountslots 16 \
  --txpool.globalslots 4096 \
  --txpool.accountqueue 64 \
  --txpool.globalqueue 1024 \
  --cache 4096 \
  --cache.gc 25 \
  --maxpeers 50 >> $LOG_FILE 2>&1 &

# Store the process ID
echo $! > $DATA_DIR/node.pid

# Wait for node to start
echo "Waiting for node to start..."
sleep 5

# Display node status
echo "Node started in background with PID: $(cat $DATA_DIR/node.pid)"
echo "Log file: $LOG_FILE"

# Get and display enode URL
echo "Getting enode URL..."
get_enode

# Add helper functions
cat << 'EOF' > node-control.sh
#!/bin/bash
DATA_DIR="node1"
IPC_PATH="$DATA_DIR/geth.ipc"

stop_node() {
    if [ -f "$DATA_DIR/node.pid" ]; then
        pid=$(cat "$DATA_DIR/node.pid")
        kill $pid
        rm "$DATA_DIR/node.pid"
        echo "Node stopped"
    else
        echo "Node not running"
    fi
}

status_node() {
    if [ -f "$DATA_DIR/node.pid" ]; then
        pid=$(cat "$DATA_DIR/node.pid")
        if ps -p $pid > /dev/null; then
            echo "Node is running with PID: $pid"
            echo "Recent logs:"
            tail -n 10 node.log
            echo -e "\nPeer count:"
            geth attach --datadir $DATA_DIR --exec 'net.peerCount'
        else
            echo "Node not running (stale PID file)"
            rm "$DATA_DIR/node.pid"
        fi
    else
        echo "Node not running"
    fi
}

add_peer() {
    if [ -z "$1" ]; then
        echo "Error: No enode URL provided"
        echo "Usage: $0 add-peer enode://nodeId@ip:port"
        return 1
    fi
    
    echo "Adding peer: $1"
    geth attach --datadir $DATA_DIR --exec "admin.addPeer('$1')"
}

remove_peer() {
    if [ -z "$1" ]; then
        echo "Error: No enode URL provided"
        echo "Usage: $0 remove-peer enode://nodeId@ip:port"
        return 1
    fi
    
    echo "Removing peer: $1"
    geth attach --datadir $DATA_DIR --exec "admin.removePeer('$1')"
}

list_peers() {
    echo "Current peers:"
    geth attach --datadir $DATA_DIR --exec 'admin.peers'
}

get_enode() {
    echo "This node's enode URL:"
    geth attach --datadir $DATA_DIR --exec 'admin.nodeInfo.enode'
}

show_sync_status() {
    echo "Sync status:"
    geth attach --datadir $DATA_DIR --exec 'eth.syncing || "Fully synced"'
    echo "Current block:"
    geth attach --datadir $DATA_DIR --exec 'eth.blockNumber'
}

case "$1" in
    stop)
        stop_node
        ;;
    status)
        status_node
        ;;
    enode)
        get_enode
        ;;
    add-peer)
        add_peer "$2"
        ;;
    remove-peer)
        remove_peer "$2"
        ;;
    peers)
        list_peers
        ;;
    sync)
        show_sync_status
        ;;
    *)
        echo "Usage: $0 {stop|status|enode|add-peer|remove-peer|peers|sync}"
        echo ""
        echo "Commands:"
        echo "  stop                    - Stop the node"
        echo "  status                  - Check node status and see recent logs"
        echo "  enode                   - Display this node's enode URL"
        echo "  add-peer <enode_url>    - Add a peer using its enode URL"
        echo "  remove-peer <enode_url> - Remove a peer using its enode URL"
        echo "  peers                   - List all connected peers"
        echo "  sync                    - Show synchronization status"
        exit 1
        ;;
esac
EOF

chmod +x node-control.sh

echo "
Node management commands available:
./node-control.sh status                  - Check node status and see recent logs
./node-control.sh stop                    - Stop the node
./node-control.sh enode                   - Display this node's enode URL
./node-control.sh add-peer <enode_url>    - Add a peer using its enode URL
./node-control.sh remove-peer <enode_url> - Remove a peer using its enode URL
./node-control.sh peers                   - List all connected peers
./node-control.sh sync                    - Show synchronization status
" 