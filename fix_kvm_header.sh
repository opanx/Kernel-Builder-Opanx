#!/bin/bash
# Fix KVM hypervisor header include path

echo "=== APPLYING KVM HEADER FIX ==="
cd "$GITHUB_WORKSPACE/kernel-source" || exit 1

# Apply the fix directly to the source file
echo "Fixing KVM sysreg-sr.c include path..."
sed -i 's/#include <hyp\/sysreg-sr.h>/#include "..\/sysreg-sr.h"/' arch/arm64/kvm/hyp/vhe/sysreg-sr.c 2>/dev/null || true

# Verify the fix was applied
if grep -q '#include "..\/sysreg-sr.h"' arch/arm64/kvm/hyp/vhe/sysreg-sr.c; then
  echo "✓ KVM header fix successfully applied"
  exit 0
else
  echo "⚠ Could not verify fix, but continuing build..."
  exit 0
fi
