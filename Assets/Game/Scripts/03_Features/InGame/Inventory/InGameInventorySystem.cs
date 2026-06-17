using System;
using System.Collections.Generic;
using Domain.InGame;

namespace Features.InGame
{
    public interface IInGameInventorySystem
    {
        IReadOnlyList<InventoryItemDTO> Items { get; }
        event Action OnInventoryChanged;
        void AddItem(InventoryItemDTO item);
        void RemoveItem(string itemId);
        bool HasItem(string itemId);
        IReadOnlyList<InventoryItemDTO> GetClues();
    }

    public class InGameInventorySystem : IInGameInventorySystem
    {
        private readonly List<InventoryItemDTO> m_items;

        public event Action OnInventoryChanged;

        public IReadOnlyList<InventoryItemDTO> Items
        {
            get
            {
                return m_items.AsReadOnly();
            }
        }

        public InGameInventorySystem()
        {
            m_items = new List<InventoryItemDTO>();
        }

        public void AddItem(InventoryItemDTO item)
        {
            if (item == null)
            {
                return;
            }
            if (HasItem(item.itemId) == true)
            {
                return;
            }
            m_items.Add(item);
            if (OnInventoryChanged != null)
            {
                OnInventoryChanged.Invoke();
            }
        }

        public void RemoveItem(string itemId)
        {
            if (string.IsNullOrEmpty(itemId) == true)
            {
                return;
            }
            int index = -1;
            for (int i = 0; i < m_items.Count; i++)
            {
                if (m_items[i].itemId == itemId)
                {
                    index = i;
                    break;
                }
            }
            if (index >= 0)
            {
                m_items.RemoveAt(index);
                if (OnInventoryChanged != null)
                {
                    OnInventoryChanged.Invoke();
                }
            }
        }

        public bool HasItem(string itemId)
        {
            if (string.IsNullOrEmpty(itemId) == true)
            {
                return false;
            }
            for (int i = 0; i < m_items.Count; i++)
            {
                if (m_items[i].itemId == itemId)
                {
                    return true;
                }
            }
            return false;
        }

        public IReadOnlyList<InventoryItemDTO> GetClues()
        {
            List<InventoryItemDTO> clues = new List<InventoryItemDTO>();
            for (int i = 0; i < m_items.Count; i++)
            {
                if (m_items[i].isClue == true)
                {
                    clues.Add(m_items[i]);
                }
            }
            return clues.AsReadOnly();
        }
    }
}
