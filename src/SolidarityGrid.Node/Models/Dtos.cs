namespace SolidarityGrid.Node.Models;

public class PaymentRequest
{
    public decimal Amount { get; set; }
    public string Currency { get; set; } = "USD";
}

public class PaymentResponse
{
    public string TransactionId { get; set; } = "";
    public string Status { get; set; } = "";
    public string Node { get; set; } = "";
    public int EstimatedDelayMs { get; set; }
}

public class ClaimRequest
{
    public string TransactionId { get; set; } = "";
    public string ClaimantNodeId { get; set; } = "";
}

public class ClaimResponse
{
    public bool Acquired { get; set; }
    public string? OwnerNodeId { get; set; }
}

public class HealthResponse
{
    public string NodeId { get; set; } = "";
    public bool Alive { get; set; }
    public int TransactionCount { get; set; }
    public int PeerCount { get; set; }
    public DateTime Timestamp { get; set; }
}
