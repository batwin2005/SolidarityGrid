using Microsoft.AspNetCore.Mvc;
using SolidarityGrid.Node.Models;
using SolidarityGrid.Node.Services;

namespace SolidarityGrid.Node.Controllers;

[ApiController]
public class NodeController : ControllerBase
{
    private readonly NodeState _state;
    private readonly ILogger<NodeController> _logger;

    public NodeController(NodeState state, ILogger<NodeController> logger)
    {
        _state = state;
        _logger = logger;
    }

    [HttpGet("health")]
    public IActionResult Health()
    {
        return Ok(new HealthResponse
        {
            NodeId = _state.NodeId,
            Alive = true,
            TransactionCount = _state.Transactions.Count,
            PeerCount = _state.PeerUrls.Count,
            Timestamp = DateTime.UtcNow
        });
    }

    [HttpPost("gossip")]
    public IActionResult ReceiveGossip([FromBody] GossipPayload payload)
    {
        if (payload?.Transactions == null)
            return BadRequest();

        foreach (var inc in payload.Transactions)
        {
            if (_state.Transactions.TryGetValue(inc.Id, out var local))
            {
                if (inc.State == TransactionState.Completed && local.State != TransactionState.Completed)
                {
                    _state.Transactions[inc.Id] = inc;
                    _logger.LogInformation("[{NodeId}] 📡 Gossip from {Source}: {TxId} → {State}",
                        _state.NodeId, payload.NodeId, inc.Id, inc.State);
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
                    _state.NodeId, payload.NodeId, inc.Id, inc.State, inc.OwnerNodeId);
            }
        }

        return Ok(new GossipPayload
        {
            NodeId = _state.NodeId,
            Timestamp = DateTime.UtcNow,
            Transactions = _state.Transactions.Values.ToList()
        });
    }

    [HttpPost("claim")]
    public IActionResult Claim([FromBody] ClaimRequest request)
    {
        if (request == null || string.IsNullOrWhiteSpace(request.TransactionId))
            return BadRequest();

        var txId = request.TransactionId.ToUpper();

        var existingOwner = _state.TransactionClaims.GetOrAdd(txId, request.ClaimantNodeId);

        if (existingOwner == request.ClaimantNodeId)
        {
            _logger.LogInformation("[{NodeId}] 🔑 Lock granted on {TxId} for [{Claimant}].",
                _state.NodeId, txId, request.ClaimantNodeId);

            return Ok(new ClaimResponse { Acquired = true, OwnerNodeId = request.ClaimantNodeId });
        }

        _logger.LogInformation("[{NodeId}] 🔒 Lock DENIED on {TxId} for [{Claimant}] (held by [{Owner}]).",
            _state.NodeId, txId, request.ClaimantNodeId, existingOwner);

        return Ok(new ClaimResponse { Acquired = false, OwnerNodeId = existingOwner });
    }
}
