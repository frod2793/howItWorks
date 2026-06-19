using System;
using System.Collections.Generic;
using Domain.InGame;

namespace Features.InGame
{
    public interface IBacklogViewModel
    {
        IReadOnlyList<BacklogItemDTO> Items { get; }
        event Action OnBacklogUpdated;
        void Clear();
        string CurrentSceneInfo { get; }
    }
}
