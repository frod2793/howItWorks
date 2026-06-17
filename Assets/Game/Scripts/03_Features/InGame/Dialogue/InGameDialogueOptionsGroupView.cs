using UnityEngine;
using System.Collections.Generic;
using System;
using Domain.InGame;

namespace Features.InGame
{
    public class InGameDialogueOptionsGroupView : MonoBehaviour
    {
        [SerializeField] private List<InGameDialogueOptionCardView> m_optionCards;

        public void SetGroupData(List<DialogueChoiceDTO> choices, Action<int> onCardSelected)
        {
            if (m_optionCards != null)
            {
                for (int i = 0; i < m_optionCards.Count; i++)
                {
                    if (m_optionCards[i] != null)
                    {
                        if (i < choices.Count)
                        {
                            m_optionCards[i].gameObject.SetActive(true);
                            m_optionCards[i].SetCardData(choices[i], onCardSelected);
                        }
                        else
                        {
                            m_optionCards[i].gameObject.SetActive(false);
                        }
                    }
                }
            }
        }
    }
}
