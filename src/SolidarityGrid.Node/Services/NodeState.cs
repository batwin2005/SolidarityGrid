using System.Collections.Concurrent;
using SolidarityGrid.Node.Models;

namespace SolidarityGrid.Node.Services;

public class NodeState
{
    public string NodeId { get; }
    public List<string> PeerUrls { get; }
    public ConcurrentDictionary<string, Transaction> Transactions { get; } = new();
    public ConcurrentDictionary<string, DateTime> PeerLastSeen { get; } = new();
    public ConcurrentDictionary<string, string> PeerNodeIds { get; } = new();
    public ConcurrentDictionary<string, string> TransactionClaims { get; } = new();

    public NodeState(IConfiguration config)
    {
        NodeId = config["NODE_ID"] ?? $"Node-{Guid.NewGuid().ToString("N")[..4]}";

        var peers = config["PEERS"] ?? "";
        PeerUrls = peers
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .ToList();
    }

    public List<string> GetAlivePeerUrls()
    {
        return PeerUrls.Where(url =>
            PeerLastSeen.TryGetValue(url, out var lastSeen) &&
            (DateTime.UtcNow - lastSeen).TotalSeconds <= 8
        ).ToList();
    }

    public bool IsPeerDead(string peerUrl)
    {
        return !PeerLastSeen.TryGetValue(peerUrl, out var lastSeen) ||
               (DateTime.UtcNow - lastSeen).TotalSeconds > 8;
    }

    public string GetPeerNodeId(string peerUrl)
    {
        if (PeerNodeIds.TryGetValue(peerUrl, out var nodeId))
            return nodeId;

        try
        {
            return new Uri(peerUrl).Host;
        }
        catch
        {
            return peerUrl;
        }
    }
}
