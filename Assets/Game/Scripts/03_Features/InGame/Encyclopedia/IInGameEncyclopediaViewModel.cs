using System;
using System.Collections.Generic;
using Domain.InGame;

/// <summary>
/// [기능]: 도감 화면의 상태 변화 및 사용자 조작 명령을 제공하는 뷰모델 인터페이스입니다.
/// [작성자]: 윤승종
/// </summary>
namespace Features.InGame
{
    public interface IInGameEncyclopediaViewModel
    {
        event Action OnDataChanged;
        event Action<EncyclopediaItemDTO> OnDetailOpened;
        event Action OnDetailClosed;

        string CurrentCategory { get; }
        bool ShowOnlyUnlocked { get; }
        IReadOnlyList<EncyclopediaItemDTO> CurrentItems { get; }
        EncyclopediaItemDTO ActiveDetailItem { get; }

        void Initialize(List<string> unlockedItems);
        void func_SelectCategory(string category);
        void func_ToggleFilter();
        void func_SelectCard(string itemId);
        void func_CloseDetail();
        (int unlocked, int total) GetCategoryProgress(string category);
    }
}
