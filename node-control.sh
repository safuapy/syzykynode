#!/bin/bash
DATA_DIR="node1"
IPC_PATH="$DATA_DIR/geth.ipc"
GETH_VERSION="1.10.15"
GETH_URL="https://gethstore.blob.core.windows.net/builds/geth-linux-amd64-1.10.15-8be800ff.tar.gz"

check_install_geth() {
    if ! command -v geth &> /dev/null; then
        echo "Geth is not installed. Installing geth ${GETH_VERSION}..."
        
        # Create temporary directory
        TMP_DIR=$(mktemp -d)
        cd $TMP_DIR

        # Download and extract geth
        if ! curl -L -o geth.tar.gz $GETH_URL; then
            echo "Failed to download geth"
            rm -rf $TMP_DIR
            return 1
        fi

        # Extract the archive
        if ! tar xzf geth.tar.gz; then
            echo "Failed to extract geth"
            rm -rf $TMP_DIR
            return 1
        fi

        # Move geth binary to /usr/local/bin
        if ! sudo mv geth-linux-amd64-${GETH_VERSION}-8be800ff/geth /usr/local/bin/; then
            echo "Failed to install geth"
            rm -rf $TMP_DIR
            return 1
        }

        # Cleanup
        cd - > /dev/null
        rm -rf $TMP_DIR

        echo "Geth ${GETH_VERSION} installed successfully"
        geth version
    else
        echo "Geth is already installed:"
        geth version
    fi
}

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

check_connectivity() {
    echo "Checking HTTP RPC connectivity..."
    if curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' \
        http://149.102.132.51:8545 > /dev/null; then
        echo "✓ HTTP RPC (8545) is accessible"
    else
        echo "✗ HTTP RPC (8545) is not accessible"
    fi

    echo -e "\nChecking WebSocket connectivity..."
    if timeout 5 bash -c "</dev/tcp/149.102.132.51/8546" 2>/dev/null; then
        echo "✓ WebSocket (8546) port is open"
    else
        echo "✗ WebSocket (8546) port is not accessible"
    fi
}

case "$1" in
    install)
        check_install_geth
        ;;
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
    check)
        check_connectivity
        ;;
    *)
        echo "Usage: $0 {install|stop|status|enode|add-peer|remove-peer|peers|sync|check}"
        echo ""
        echo "Commands:"
        echo "  install                 - Check and install geth if needed"
        echo "  stop                    - Stop the node"
        echo "  status                  - Check node status and see recent logs"
        echo "  enode                   - Display this node's enode URL"
        echo "  add-peer <enode_url>    - Add a peer using its enode URL"
        echo "  remove-peer <enode_url> - Remove a peer using its enode URL"
        echo "  peers                   - List all connected peers"
        echo "  sync                    - Show synchronization status"
        echo "  check                   - Check RPC and WebSocket connectivity"
        exit 1
        ;;
esac
