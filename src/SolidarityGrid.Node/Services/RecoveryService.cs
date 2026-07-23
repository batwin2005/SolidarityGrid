using SolidarityGrid.Node.Models;
using System.Net.Http.Json;

namespace SolidarityGrid.Node.Services;

public class RecoveryService : BackgroundService
{
    private readonly NodeState _state;
    private readonly ILogger<RecoveryService> _logger;
    private static readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(5) };

    public RecoveryService(NodeState state, ILogger<RecoveryService> logger)
    {
        _state = state;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        await Task.Delay(5000, ct);

        while (!ct.IsCancellationRequested)
        {
            var deadPeers = _state.PeerUrls
                .Where(url => _state.IsPeerDead(url))
                .ToList();

            foreach (var deadPeerUrl in deadPeers)
            {
                var deadNodeId = _state.GetPeerNodeId(deadPeerUrl);
                _logger.LogInformation("[{NodeId}] Checking peer [{DeadUrl}] -> nodeId=[{DeadNodeId}]",
                    _state.NodeId, deadPeerUrl, deadNodeId);

                var orphaned = _state.Transactions.Values
                    .Where(t => t.OwnerNodeId == deadNodeId && t.State == TransactionState.Processing)
                    .ToList();

                foreach (var tx in orphaned)
                {
                    _logger.LogWarning("[{NodeId}] ⚠ Peer [{DeadNode}] appears dead. Investigating orphaned transaction {TxId}...",
                        _state.NodeId, deadNodeId, tx.Id);

                    var acquired = await TryAcquireLock(tx.Id, ct);

                    if (acquired)
                    {
                        _logger.LogInformation("[{NodeId}] 🔄 Acquired lock on orphaned {TxId}. Taking over from [{DeadNode}].",
                            _state.NodeId, tx.Id, deadNodeId);

                        tx.OwnerNodeId = _state.NodeId;
                        tx.State = TransactionState.Completed;
                        tx.CompletedAt = DateTime.UtcNow;
                        _state.Transactions[tx.Id] = tx;

                        _logger.LogInformation("[{NodeId}] ✓ Transaction {TxId} recovered and marked COMPLETED.",
                            _state.NodeId, tx.Id);
                    }
                    else
                    {
                        _logger.LogInformation("[{NodeId}] ℹ Another node is handling orphaned {TxId}. Standing down.",
                            _state.NodeId, tx.Id);
                    }
                }
            }

            await Task.Delay(3000, ct);
        }
    }

    private async Task<bool> TryAcquireLock(string txId, CancellationToken ct)
    {
        var alivePeers = _state.GetAlivePeerUrls();

        if (alivePeers.Count == 0)
        {
            return true;
        }

        var claimed = true;

        foreach (var peerUrl in alivePeers)
        {
            try
            {
                var request = new ClaimRequest { TransactionId = txId, ClaimantNodeId = _state.NodeId };
                var response = await _http.PostAsJsonAsync($"{peerUrl}/claim", request, ct);
                if (response.IsSuccessStatusCode)
                {
                    var result = await response.Content.ReadFromJsonAsync<ClaimResponse>(ct);
                    if (result != null && !result.Acquired)
                    {
                        claimed = false;
                    }
                }
                else
                {
                    claimed = false;
                }
            }
            catch
            {
                claimed = false;
            }
        }

        return claimed;
    }
}
