namespace SolidarityGrid.Node.Models;

public class GossipPayload
{
    public string NodeId { get; set; } = "";
    public List<Transaction> Transactions { get; set; } = new();
    public DateTime Timestamp { get; set; }
}
