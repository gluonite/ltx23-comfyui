#!/bin/bash
# Patch Linux standalone sur le node VRGDG
# Copié dans l'image Docker, appelé aussi manuellement si besoin
VRGDG_FILE="/comfyui/custom_nodes/comfyui-vrgamedevgirl/LTXLoraTrain.py"
if [ -f "$VRGDG_FILE" ]; then
    sed -i 's|Scripts/python\.exe|bin/python|g' "$VRGDG_FILE"
    sed -i 's|Scripts", "python\.exe"|bin", "python"|g' "$VRGDG_FILE"
    sed -i 's|"Scripts"|"bin"|g' "$VRGDG_FILE"
    sed -i 's|python\.exe|python|g' "$VRGDG_FILE"
    sed -i 's|accelerate\.exe|accelerate|g' "$VRGDG_FILE"
    echo "✅ Patch VRGDG appliqué."
else
    echo "❌ LTXLoraTrain.py absent — node VRGDG pas encore installé."
fi
