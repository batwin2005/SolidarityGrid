using SolidarityGrid.Node.Models;
using System.Net.Http.Json;
using System.Text.Json;

namespace SolidarityGrid.Node.Services;

public class GossipService : BackgroundService
{
    private readonly NodeState _state;
    private readonly ILogger<GossipService> _logger;
    private static readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(5) };

    public GossipService(NodeState state, ILogger<GossipService> logger)
    {
        _state = state;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        await Task.Delay(2000, ct);

        while (!ct.IsCancellationRequested)
        {
            var alivePeers = _state.GetAlivePeerUrls();

            if (alivePeers.Count > 0)
            {
                var payload = new GossipPayload
                {
                    NodeId = _state.NodeId,
                    Timestamp = DateTime.UtcNow,
                    Transactions = _state.Transactions.Values.ToList()
                };

                foreach (var peerUrl in alivePeers)
                {
                    try
                    {
                        var response = await _http.PostAsJsonAsync($"{peerUrl}/gossip", payload, ct);
                        if (response.IsSuccessStatusCode)
                        {
                            var peerState = await response.Content.ReadFromJsonAsync<GossipPayload>(ct);
                            if (peerState?.Transactions != null)
                            {
                                MergeTransactions(peerState.Transactions, peerState.NodeId);
                            }
                        }
                    }
                    catch
                    {
                    }
                }
            }

            await Task.Delay(2000, ct);
        }
    }

    private void MergeTransactions(List<Transaction> incoming, string sourceNodeId)
    {
        foreach (var inc in incoming)
        {
            if (_state.Transactions.TryGetValue(inc.Id, out var local))
            {
                if (inc.State == TransactionState.Completed && local.State != TransactionState.Completed)
                {
                    _state.Transactions[inc.Id] = inc;
                    _logger.LogInformation("[{NodeId}] 📡 Gossip from {Source}: {TxId} → {State}",
                        _state.NodeId, sourceNodeId, inc.Id, inc.State);
                }
                else if (inc.State == TransactionState.Processing && local.State == TransactionState.Pending)
                {
                    _state.Transactions[inc.Id] = inc;
                }
            }
            else
            {
                _state.Transactions[inc.Id] = inc;
                _logger.LogInformation("[{NodeId}] 📡 Gossip from {Source}: new tx {TxId} ({State}, owner={Owner})",
                    _state.NodeId, sourceNodeId, inc.Id, inc.State, inc.OwnerNodeId);
            }
        }
    }

    public async Task BroadcastImmediate(Transaction tx)
    {
        var payload = new GossipPayload
        {
            NodeId = _state.NodeId,
            Timestamp = DateTime.UtcNow,
            Transactions = new List<Transaction> { tx }
        };

        foreach (var peerUrl in _state.PeerUrls)
        {
            try
            {
                await _http.PostAsJsonAsync($"{peerUrl}/gossip", payload);
            }
            catch
            {
            }
        }
    }
}
