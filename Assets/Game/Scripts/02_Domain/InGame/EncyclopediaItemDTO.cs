/// <summary>
/// [기능]: 도감의 개별 아이템 데이터를 표현하는 순수 C# DTO 클래스입니다.
/// [작성자]: 윤승종
/// </summary>
namespace Domain.InGame
{
    public class EncyclopediaItemDTO
    {
        public string Id { get; set; }
        public string Name { get; set; }
        public string Description { get; set; }
        public string Tag { get; set; }
        public string Category { get; set; }
        public string IconPath { get; set; }
        public bool IsUnlocked { get; set; }
    }
}
