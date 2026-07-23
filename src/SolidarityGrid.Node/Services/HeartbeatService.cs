using SolidarityGrid.Node.Models;
using System.Net.Http.Json;

namespace SolidarityGrid.Node.Services;

public class HeartbeatService : BackgroundService
{
    private readonly NodeState _state;
    private readonly ILogger<HeartbeatService> _logger;
    private static readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(4) };

    private static readonly string[] _spinner = { "◐", "◓", "◑", "◒" };

    public HeartbeatService(NodeState state, ILogger<HeartbeatService> logger)
    {
        _state = state;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        await Task.Delay(1000, ct);

        while (!ct.IsCancellationRequested)
        {
            foreach (var peerUrl in _state.PeerUrls)
            {
                try
                {
                    var response = await _http.GetAsync($"{peerUrl}/health", ct);
                    if (response.IsSuccessStatusCode)
                    {
                        var health = await response.Content.ReadFromJsonAsync<HealthResponse>(ct);
                        if (health != null)
                        {
                            _state.PeerLastSeen[peerUrl] = DateTime.UtcNow;
                            _state.PeerNodeIds[peerUrl] = health.NodeId;

                            if (_state.IsPeerDead(peerUrl) == false)
                            {
                                _logger.LogDebug("[{NodeId}] ♥ Heartbeat OK from {Peer}", _state.NodeId, health.NodeId);
                            }
                        }
                    }
                }
                catch (Exception ex)
                {
                    var wasAlive = !_state.IsPeerDead(peerUrl);
                    if (wasAlive)
                    {
                        var peerNode = _state.GetPeerNodeId(peerUrl);
                        _logger.LogWarning("[{NodeId}] ♡ Heartbeat MISS from {Peer} ({ShortMsg})",
                            _state.NodeId, peerNode, ex.Message);
                    }
                }
            }

            await Task.Delay(2000, ct);
        }
    }
}
