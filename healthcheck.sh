isReady=0
for i in $(seq 1 10); do
  echo "Tentative $i/10..."
  sleep 10
  status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8070/health || echo "000")
  echo "Code HTTP: $status"
  if [ "$status" = "200" ]; then
    isReady=1
    echo "Health Check reussi ! L application est joignable."
    break
  fi
done
if [ "$isReady" -eq 0 ]; then
  echo "Echec. Logs:"
  docker logs shopping-cart
  exit 1
fi
