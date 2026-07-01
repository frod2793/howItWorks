using System;
using System.Collections.Generic;
using Domain.InGame;

namespace Features.InGame
{
    public interface IBacklogViewModel
    {
        IReadOnlyList<BacklogItemDTO> Items { get; }
        event Action OnBacklogUpdated;
        event Action<int> OnRequestJump;
        void Clear();
        void JumpToLine(int dialogueIndex);
        string CurrentSceneInfo { get; }
    }
}
