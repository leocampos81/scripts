'EOF'
#!/bin/bash
while true; do
    clear
    echo "=== MONITOR RAM/SWAP - $(date +%T) ==="
    
    echo -e "\n[MEMORIA GENERAL]"
    free -h
    
    echo -e "\n[DETALLE SWAP (ZRAM vs DISCO)]"
    swapon --show
    
    echo -e "\n[TOP 5 PROCESOS QUE COMEN RAM]"
    ps aux --sort=-%mem | head -6
    
    sleep 2
done
EOF
